import Foundation

struct CertificateService {
    private static let distDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/ota")
    private static let certsDir = distDir.appendingPathComponent("certs")
    
    static func ensureDirectories() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: distDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: certsDir, withIntermediateDirectories: true)
    }
    
    static func fetchTailscaleCerts(hostname: String) throws -> CertificateFiles {
        ensureDirectories()
        
        let certPath = certsDir.appendingPathComponent("server.crt").path
        let keyPath = certsDir.appendingPathComponent("server.key").path
        
        Logger.info("Fetching Tailscale TLS certificates...")
        
        let command = "tailscale cert --cert-file \"\(certPath)\" --key-file \"\(keyPath)\" \"\(hostname)\""
        _ = try ShellService.run(command)
        
        let exists = FileManager.default.fileExists(atPath: certPath) && FileManager.default.fileExists(atPath: keyPath)
        
        return CertificateFiles(
            certPath: certPath,
            keyPath: keyPath,
            exists: exists
        )
    }
    
    static func generateSelfSignedCerts() throws -> CertificateFiles {
        ensureDirectories()
        
        let certPath = certsDir.appendingPathComponent("server.crt").path
        let keyPath = certsDir.appendingPathComponent("server.key").path
        
        if FileManager.default.fileExists(atPath: certPath) && FileManager.default.fileExists(atPath: keyPath) {
            return CertificateFiles(certPath: certPath, keyPath: keyPath, exists: true)
        }
        
        Logger.info("Generating self-signed certificates for development...")
        
        let command = "openssl req -x509 -newkey rsa:4096 -keyout \"\(keyPath)\" -out \"\(certPath)\" -days 365 -nodes -subj \"/CN=localhost\""
        _ = try ShellService.run(command)
        
        let exists = FileManager.default.fileExists(atPath: certPath) && FileManager.default.fileExists(atPath: keyPath)
        
        guard exists else {
            throw OTAError.certificateGenerationFailed
        }
        
        return CertificateFiles(
            certPath: certPath,
            keyPath: keyPath,
            exists: exists
        )
    }
}