import ArgumentParser
import Foundation

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct OTAHostCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-ota-host",
        abstract: "iOS App Over-The-Air Distribution Server",
        discussion: """
        A Swift-based OTA distribution server for iOS apps. 
        Automatically finds IPA files in the current directory and serves them for installation.
        
        Examples:
          swift-ota-host --dev                    # Development mode
          swift-ota-host --port 443               # Production mode on port 443
          swift-ota-host --dev --port 9000        # Custom port in dev mode
          swift-ota-host --ipa MyApp.ipa --once   # Specific IPA, exit after serving
        """
    )
    
    @Flag(name: .long, help: "Development mode (self-signed certs, localhost)")
    var dev = false
    
    @Option(name: .long, help: "Server port (default: 443 prod, 8443 dev)")
    var port: Int?
    
    @Option(name: .long, help: "Use specific IPA file")
    var ipa: String?
    
    @Flag(name: .long, help: "Exit after serving the first IPA file")
    var once = false
    
    @Flag(name: .long, help: "Disable HTTPS (not recommended)")
    var noHttps = false
    
    mutating func validate() throws {
        if let port = port {
            guard port > 0 && port <= 65535 else {
                throw ValidationError("Port must be between 1 and 65535")
            }
        }
        
        if let ipa = ipa {
            guard FileManager.default.fileExists(atPath: ipa) else {
                throw ValidationError("Custom IPA file not found: \(ipa)")
            }
            
            guard ipa.lowercased().hasSuffix(".ipa") else {
                throw ValidationError("Custom file must have .ipa extension")
            }
        }
    }
    
    mutating func run() async throws {
        let config = ServerConfig(
            port: port ?? (dev ? 8443 : 443),
            devMode: dev,
            customIpaPath: ipa,
            hostname: dev ? "localhost" : "0.0.0.0",
            useHttps: !noHttps,
            once: once
        )
        
        // Print configuration info
        Logger.info("OTA Host - iOS App Over-The-Air Distribution")
        Logger.info("Configuration:")
        Logger.info("  Port: \(config.port)")
        Logger.info("  Mode: \(config.devMode ? "Development" : "Production")")
        Logger.info("  HTTPS: \(config.useHttps ? "Enabled" : "Disabled")")
        Logger.info("  Once: \(config.once ? "Yes" : "No")")
        if let customIpa = config.customIpaPath {
            Logger.info("  Custom IPA: \(customIpa)")
        }
        Logger.info("")
        
        let otaHost = OTAHost(config: config)
        
        do {
            try await otaHost.start()
        } catch {
            Logger.error("Fatal error: \(error.localizedDescription)")
            
            // Print more helpful error messages
            switch error {
            case OTAError.noIPAFiles:
                Logger.info("Make sure you have IPA files in the current directory")
            case OTAError.tailscaleNotAvailable:
                Logger.info("In production mode, Tailscale must be running")
                Logger.info("Use --dev flag for development mode with self-signed certificates")
            case OTAError.certificateGenerationFailed:
                Logger.info("Certificate generation failed. Make sure OpenSSL is installed")
            default:
                break
            }
            
            throw ExitCode.failure
        }
    }
}