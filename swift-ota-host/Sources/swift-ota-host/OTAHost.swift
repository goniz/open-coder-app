import Foundation

class OTAHost {
    private let config: ServerConfig
    private var server: HTTPServer?
    
    init(config: ServerConfig) {
        self.config = config
    }
    
    func start() async throws {
        Logger.debug("Starting OTA Host...")
        
        // Find IPA files
        let ipaFiles = try IPAService.findIPAFiles()
        guard !ipaFiles.isEmpty else {
            throw OTAError.noIPAFiles
        }
        
        let latestIpa = ipaFiles[0]
        Logger.info("Using IPA: \(latestIpa.displayName) v\(latestIpa.version)")
        
        // Setup hostname and certificates
        let hostname: String
        
        if config.devMode {
            hostname = config.hostname
        } else {
            let tailscaleStatus = TailscaleService.getStatus()
            guard tailscaleStatus.isRunning, let tsHostname = tailscaleStatus.hostname else {
                throw OTAError.tailscaleNotAvailable
            }
            hostname = tsHostname
        }
        
        let protocolScheme = config.useHttps ? "https" : "http"
        let baseUrl = "\(protocolScheme)://\(hostname):\(config.port)"
        
        // Generate manifest and install page files
        try await generateFiles(ipaInfo: latestIpa, baseUrl: baseUrl)
        
        // Start HTTP server
        server = HTTPServer(ipaInfo: latestIpa, config: config, baseUrl: baseUrl)
        
        // Setup graceful shutdown
        setupSignalHandlers()
        
        try await server?.start()
    }
    
    private func generateFiles(ipaInfo: IPAInfo, baseUrl: String) async throws {
        let distDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/ota")
        
        // Ensure dist directory exists
        try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
        
        // Generate manifest.plist
        let manifestData = ManifestData(
            bundleId: ipaInfo.bundleId,
            version: ipaInfo.version,
            title: ipaInfo.displayName,
            ipaUrl: "\(baseUrl)/latest.ipa",
            iconUrls: ManifestData.IconUrls(
                small: "\(baseUrl)/icon57.png",
                large: "\(baseUrl)/icon512.png"
            )
        )
        
        let manifest = Templates.manifestPlist(
            bundleId: manifestData.bundleId,
            version: manifestData.version,
            title: manifestData.title,
            ipaUrl: manifestData.ipaUrl
        )
        
        let manifestPath = distDir.appendingPathComponent("manifest.plist")
        try manifest.write(to: manifestPath, atomically: true, encoding: .utf8)
        Logger.debug("Generated manifest.plist")
        
        // Generate install.html
        let installUrl = "itms-services://?action=download-manifest&url=\(baseUrl)/manifest.plist"
        let html = Templates.installHTML(
            appName: ipaInfo.displayName,
            version: ipaInfo.version,
            bundleId: ipaInfo.bundleId,
            installUrl: installUrl,
            fileSize: ipaInfo.size.formatFileSize()
        )
        
        let installPath = distDir.appendingPathComponent("install.html")
        try html.write(to: installPath, atomically: true, encoding: .utf8)
        Logger.debug("Generated install.html")
    }
    
    private func setupSignalHandlers() {
        let signalQueue = DispatchQueue(label: "signals", qos: .background)
        
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
        
        sigintSource.setEventHandler {
            Logger.info("Received SIGINT, shutting down...")
            Task {
                await self.shutdown()
            }
        }
        
        sigtermSource.setEventHandler {
            Logger.info("Received SIGTERM, shutting down...")
            Task {
                await self.shutdown()
            }
        }
        
        sigintSource.resume()
        sigtermSource.resume()
    }
    
    private func shutdown() async {
        Logger.info("Shutting down server...")
        await server?.stop()
        exit(0)
    }
}