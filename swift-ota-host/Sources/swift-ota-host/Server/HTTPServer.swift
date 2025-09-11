import Foundation
import NIO
import NIOHTTP1
import NIOSSL

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private let ipaInfo: IPAInfo
    private let config: ServerConfig
    private let baseUrl: String
    private let distDir: URL
    
    init(ipaInfo: IPAInfo, config: ServerConfig, baseUrl: String) {
        self.ipaInfo = ipaInfo
        self.config = config
        self.baseUrl = baseUrl
        self.distDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/ota")
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = self.unwrapInboundIn(data)
        
        switch request {
        case .head(let header):
            handleRoute(header.uri, context: context)
        case .body, .end:
            break
        }
    }
    
    private func handleRoute(_ uri: String, context: ChannelHandlerContext) {
        switch uri {
        case "/":
            serveInstallPage(context: context)
        case "/manifest.plist":
            serveManifest(context: context)
        case "/latest.ipa":
            serveIPA(context: context)
        default:
            serve404(context: context)
        }
    }
    
    private func serveInstallPage(context: ChannelHandlerContext) {
        let installUrl = "itms-services://?action=download-manifest&url=\(baseUrl)/manifest.plist"
        let html = Templates.installHTML(
            appName: ipaInfo.displayName,
            version: ipaInfo.version,
            bundleId: ipaInfo.bundleId,
            installUrl: installUrl,
            fileSize: ipaInfo.size.formatFileSize()
        )
        
        sendResponse(context: context, content: html, contentType: "text/html")
    }
    
    private func serveManifest(context: ChannelHandlerContext) {
        let manifest = Templates.manifestPlist(
            bundleId: ipaInfo.bundleId,
            version: ipaInfo.version,
            title: ipaInfo.displayName,
            ipaUrl: "\(baseUrl)/latest.ipa"
        )
        
        sendResponse(context: context, content: manifest, contentType: "application/xml")
    }
    
    private func serveIPA(context: ChannelHandlerContext) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: ipaInfo.path)) else {
            serve404(context: context)
            return
        }
        
        if config.once {
            Logger.info("IPA download started, will exit after completion due to --once flag")
        }
        
        sendBinaryResponse(context: context, data: data, contentType: "application/octet-stream") {
            if self.config.once {
                Logger.info("IPA download completed, shutting down server...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    exit(0)
                }
            }
        }
    }
    
    private func serve404(context: ChannelHandlerContext) {
        let html = "<html><body><h1>404 Not Found</h1></body></html>"
        sendResponse(context: context, content: html, contentType: "text/html", status: .notFound)
    }
    
    private func sendResponse(context: ChannelHandlerContext, content: String, contentType: String, status: HTTPResponseStatus = .ok) {
        let data = content.data(using: .utf8) ?? Data()
        
        let head = HTTPResponseHead(
            version: .http1_1,
            status: status,
            headers: [
                "Content-Type": contentType,
                "Content-Length": "\(data.count)"
            ]
        )
        
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        
        let buffer = context.channel.allocator.buffer(bytes: data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
    
    private func sendBinaryResponse(context: ChannelHandlerContext, data: Data, contentType: String, completion: @escaping () -> Void = {}) {
        let head = HTTPResponseHead(
            version: .http1_1,
            status: .ok,
            headers: [
                "Content-Type": contentType,
                "Content-Length": "\(data.count)"
            ]
        )
        
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        
        let buffer = context.channel.allocator.buffer(bytes: data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        
        let promise = context.eventLoop.makePromise(of: Void.self)
        promise.futureResult.whenComplete { _ in
            completion()
        }
        
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: promise)
    }
}

final class HTTPServer: @unchecked Sendable {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    private var channel: Channel?
    private let ipaInfo: IPAInfo
    private let config: ServerConfig
    private let baseUrl: String
    
    init(ipaInfo: IPAInfo, config: ServerConfig, baseUrl: String) {
        self.ipaInfo = ipaInfo
        self.config = config
        self.baseUrl = baseUrl
    }
    
    func start() async throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                if self.config.useHttps {
                    return self.configureHTTPS(channel: channel)
                } else {
                    return self.configureHTTP(channel: channel)
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
        
        channel = try await bootstrap.bind(host: "0.0.0.0", port: config.port).get()
        
        Logger.info("🚀 OTA Server started")
        Logger.info("📱 App: \(ipaInfo.displayName) v\(ipaInfo.version)")
        Logger.info("🌐 Install URL: \(baseUrl)/")
        Logger.info("📋 Direct install: itms-services://?action=download-manifest&url=\(baseUrl)/manifest.plist")
        Logger.info("⚙️  Mode: \(config.devMode ? "Development" : "Production")")
        
        try await channel?.closeFuture.get()
    }
    
    private func configureHTTP(channel: Channel) -> EventLoopFuture<Void> {
        return channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandler(HTTPHandler(ipaInfo: self.ipaInfo, config: self.config, baseUrl: self.baseUrl))
        }
    }
    
    private func configureHTTPS(channel: Channel) -> EventLoopFuture<Void> {
        let certs: CertificateFiles
        
        do {
            if config.devMode {
                certs = try CertificateService.generateSelfSignedCerts()
            } else {
                let tailscaleStatus = TailscaleService.getStatus()
                guard tailscaleStatus.isRunning, let hostname = tailscaleStatus.hostname else {
                    throw OTAError.tailscaleNotAvailable
                }
                certs = try CertificateService.fetchTailscaleCerts(hostname: hostname)
            }
            
            guard certs.exists else {
                throw OTAError.certificateGenerationFailed
            }
            
            let certData = try Data(contentsOf: URL(fileURLWithPath: certs.certPath))
            let keyData = try Data(contentsOf: URL(fileURLWithPath: certs.keyPath))
            
            let cert = try NIOSSLCertificate(bytes: Array(certData), format: .pem)
            let key = try NIOSSLPrivateKey(bytes: Array(keyData), format: .pem)
            
            let tlsConfig = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(cert)],
                privateKey: .privateKey(key)
            )
            
            let sslContext = try NIOSSLContext(configuration: tlsConfig)
            let sslHandler = NIOSSLServerHandler(context: sslContext)
            
            return channel.pipeline.addHandler(sslHandler).flatMap {
                channel.pipeline.configureHTTPServerPipeline()
            }.flatMap {
                channel.pipeline.addHandler(HTTPHandler(ipaInfo: self.ipaInfo, config: self.config, baseUrl: self.baseUrl))
            }
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
        }
    }
    
    func stop() async {
        try? await channel?.close().get()
        try? await group.shutdownGracefully()
    }
}