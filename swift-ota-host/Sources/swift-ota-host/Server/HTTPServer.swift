import Foundation
@preconcurrency import NIO
@preconcurrency import NIOHTTP1
@preconcurrency import NIOSSL

// Manages graceful exit in --once mode with idle timeout after last download
final class OnceExitManager {
    private let idleSeconds: TimeInterval
    private let queue = DispatchQueue(label: "swift-ota-host.once-exit")
    private var pending: DispatchWorkItem?

    init(idleSeconds: TimeInterval) {
        self.idleSeconds = idleSeconds
    }

    func downloadCompleted() {
        queue.async {
            // Cancel any existing scheduled exit and schedule a new one
            self.pending?.cancel()
            let work = DispatchWorkItem { [idle = self.idleSeconds] in
                Logger.info("⏳ No downloads for \(Int(idle))s after completion; exiting due to --once")
                exit(0)
            }
            self.pending = work
            Logger.info("⏱️  Scheduling exit in \(Int(self.idleSeconds))s if no more downloads complete")
            self.queue.asyncAfter(deadline: .now() + self.idleSeconds, execute: work)
        }
    }
}

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private let ipaInfo: IPAInfo
    private let config: ServerConfig
    private let baseUrl: String
    private let distDir: URL
    private var pendingRequest: HTTPRequestHead?
    private let onceExitManager: OnceExitManager?
    
    init(ipaInfo: IPAInfo, config: ServerConfig, baseUrl: String, onceExitManager: OnceExitManager?) {
        self.ipaInfo = ipaInfo
        self.config = config
        self.baseUrl = baseUrl
        self.distDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/ota")
        self.onceExitManager = onceExitManager
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = self.unwrapInboundIn(data)
        
        switch request {
        case .head(let header):
            self.pendingRequest = header
        case .body:
            // For this server, we don't need to handle request bodies
            break
        case .end:
            // Request is complete, now we can respond
            if let header = self.pendingRequest {
                handleRoute(header.uri, context: context)
                self.pendingRequest = nil
            }
        }
    }
    
    private func handleRoute(_ uri: String, context: ChannelHandlerContext) {
        let clientAddress = context.remoteAddress?.description ?? "unknown"
        Logger.info("📥 \(clientAddress) - \(uri)")
        
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
        
        Logger.info("📄 Serving install page")
        sendResponse(context: context, content: html, contentType: "text/html")
    }
    
    private func serveManifest(context: ChannelHandlerContext) {
        let manifest = Templates.manifestPlist(
            bundleId: ipaInfo.bundleId,
            version: ipaInfo.version,
            title: ipaInfo.displayName,
            ipaUrl: "\(baseUrl)/latest.ipa"
        )
        
        Logger.info("📋 Serving manifest.plist")
        sendResponse(context: context, content: manifest, contentType: "application/xml")
    }
    
    private func serveIPA(context: ChannelHandlerContext) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: ipaInfo.path)) else {
            Logger.info("❌ IPA file not found: \(ipaInfo.path)")
            serve404(context: context)
            return
        }
        
        Logger.info("📦 Serving IPA file (\(data.count.formatFileSize()))")
        
        if config.once {
            Logger.info("IPA download started; --once idle shutdown will be scheduled upon completion")
        }
        
        sendBinaryResponse(context: context, data: data, contentType: "application/octet-stream") {
            Logger.info("✅ IPA download completed")
            if self.config.once {
                self.onceExitManager?.downloadCompleted()
            }
        }
    }
    
    private func serve404(context: ChannelHandlerContext) {
        let html = "<html><body><h1>404 Not Found</h1></body></html>"
        Logger.info("🚫 404 Not Found")
        sendResponse(context: context, content: html, contentType: "text/html", status: .notFound)
    }
    
    private func sendResponse(context: ChannelHandlerContext, content: String, contentType: String, status: HTTPResponseStatus = .ok) {
        let data = content.data(using: .utf8) ?? Data()
        
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: "\(data.count)")
        headers.add(name: "Connection", value: "close")
        
        let head = HTTPResponseHead(
            version: .http1_1,
            status: status,
            headers: headers
        )
        
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        
        let buffer = context.channel.allocator.buffer(bytes: data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        
        let promise = context.eventLoop.makePromise(of: Void.self)
        promise.futureResult.whenComplete { _ in
            context.close(promise: nil)
        }
        
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: promise)
    }
    
    private func sendBinaryResponse(context: ChannelHandlerContext, data: Data, contentType: String, completion: @escaping () -> Void = {}) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: "\(data.count)")
        headers.add(name: "Connection", value: "close")
        
        let head = HTTPResponseHead(
            version: .http1_1,
            status: .ok,
            headers: headers
        )
        
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        
        let buffer = context.channel.allocator.buffer(bytes: data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        
        let promise = context.eventLoop.makePromise(of: Void.self)
        promise.futureResult.whenComplete { _ in
            completion()
            context.close(promise: nil)
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
    private var certificates: CertificateFiles?
    private let onceExitManager: OnceExitManager?
    
    init(ipaInfo: IPAInfo, config: ServerConfig, baseUrl: String) {
        self.ipaInfo = ipaInfo
        self.config = config
        self.baseUrl = baseUrl
        self.onceExitManager = config.once ? OnceExitManager(idleSeconds: 5) : nil
    }
    
    func start() async throws {
        // Setup signal handling for graceful shutdown
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler {
            Logger.info("\n🛑 Received SIGINT, shutting down gracefully...")
            Task {
                await self.stop()
                exit(0)
            }
        }
        signalSource.resume()
        signal(SIGINT, SIG_IGN) // Ignore default SIGINT handler
        
        // Fetch certificates during startup if HTTPS is enabled
        if config.useHttps {
            try await fetchCertificates()
        }
        
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
        
        Logger.info("🔄 Binding to \(config.hostname):\(config.port)...")
        
        do {
            channel = try await bootstrap.bind(host: config.hostname, port: config.port).get()
            Logger.info("🚀 OTA Server started successfully")
            Logger.info("📱 App: \(ipaInfo.displayName) v\(ipaInfo.version)")
            Logger.info("🌐 Install URL: \(baseUrl)/")
            Logger.info("📋 Direct install: itms-services://?action=download-manifest&url=\(baseUrl)/manifest.plist")
            Logger.info("⚙️  Mode: \(config.devMode ? "Development" : "Production")")
            Logger.info("💡 Press Ctrl+C to stop the server")
            
            try await channel?.closeFuture.get()
        } catch {
            Logger.error("❌ Failed to bind to \(config.hostname):\(config.port) - \(error)")
            throw error
        }
    }
    
    private func fetchCertificates() async throws {
        Logger.info("🔐 Setting up certificates...")
        
        let certs: CertificateFiles
        
        if config.devMode {
            certs = try CertificateService.generateSelfSignedCerts()
        } else {
            let tailscaleStatus = TailscaleService.getStatus()
            
            guard tailscaleStatus.isRunning, let hostname = tailscaleStatus.hostname else {
                Logger.error("❌ Tailscale not available")
                throw OTAError.tailscaleNotAvailable
            }
            certs = try CertificateService.fetchTailscaleCerts(hostname: hostname)
        }
        
        guard certs.exists else {
            Logger.error("❌ Certificate setup failed")
            throw OTAError.certificateGenerationFailed
        }
        
        // Quick validation
        let certData = try Data(contentsOf: URL(fileURLWithPath: certs.certPath))
        let keyData = try Data(contentsOf: URL(fileURLWithPath: certs.keyPath))
        _ = try NIOSSLCertificate(bytes: Array(certData), format: .pem)
        _ = try NIOSSLPrivateKey(bytes: Array(keyData), format: .pem)
        
        self.certificates = certs
    }
    
    private func configureHTTP(channel: Channel) -> EventLoopFuture<Void> {
        return channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandler(HTTPHandler(ipaInfo: self.ipaInfo, config: self.config, baseUrl: self.baseUrl, onceExitManager: self.onceExitManager))
        }
    }
    
    private func configureHTTPS(channel: Channel) -> EventLoopFuture<Void> {
        do {
            guard let certs = self.certificates else {
                Logger.error("❌ No certificates available")
                throw OTAError.certificateGenerationFailed
            }
            
            let certData = try Data(contentsOf: URL(fileURLWithPath: certs.certPath))
            let keyData = try Data(contentsOf: URL(fileURLWithPath: certs.keyPath))
            let cert = try NIOSSLCertificate(bytes: Array(certData), format: .pem)
            let key = try NIOSSLPrivateKey(bytes: Array(keyData), format: .pem)
            
            var tlsConfig = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(cert)],
                privateKey: .privateKey(key)
            )
            tlsConfig.applicationProtocols = ["http/1.1"]
            
            let sslContext = try NIOSSLContext(configuration: tlsConfig)
            let sslHandler = NIOSSLServerHandler(context: sslContext)
            
            return channel.pipeline.addHandler(sslHandler).flatMap {
                channel.pipeline.configureHTTPServerPipeline()
            }.flatMap {
                channel.pipeline.addHandler(HTTPHandler(ipaInfo: self.ipaInfo, config: self.config, baseUrl: self.baseUrl, onceExitManager: self.onceExitManager))
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
