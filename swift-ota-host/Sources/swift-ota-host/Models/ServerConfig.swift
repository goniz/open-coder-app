import Foundation

struct ServerConfig: Codable, Equatable {
    let port: Int
    let devMode: Bool
    let customIpaPath: String?
    let hostname: String
    let useHttps: Bool
    let once: Bool
    
    static let `default` = ServerConfig(
        port: 8443,
        devMode: true,
        customIpaPath: nil,
        hostname: "localhost",
        useHttps: true,
        once: false
    )
}

struct CertificateFiles: Codable, Equatable {
    let certPath: String
    let keyPath: String
    let exists: Bool
    
    static let mock = CertificateFiles(
        certPath: "/tmp/cert.pem",
        keyPath: "/tmp/key.pem",
        exists: false
    )
}