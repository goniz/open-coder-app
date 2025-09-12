import Foundation

struct IPAInfo: Codable, Equatable, Identifiable {
    let id = UUID()
    let path: String
    let bundleId: String
    let version: String
    let displayName: String
    let buildNumber: String?
    let size: Int
    let modifiedTime: Date
    
    enum CodingKeys: String, CodingKey {
        case path, bundleId, version, displayName, buildNumber, size, modifiedTime
    }
}

struct IPAMetadata: Codable, Equatable {
    let bundleId: String
    let version: String
    let displayName: String
    let buildNumber: String?
    
    static let mock = IPAMetadata(
        bundleId: "com.example.app",
        version: "1.0.0",
        displayName: "Example App",
        buildNumber: "1"
    )
}