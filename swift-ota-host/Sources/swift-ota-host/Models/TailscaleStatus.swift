import Foundation

struct TailscaleStatus: Codable, Equatable {
    let isRunning: Bool
    let hostname: String?
    let machineName: String?
    let tailnetName: String?
    
    static let notRunning = TailscaleStatus(
        isRunning: false,
        hostname: nil,
        machineName: nil,
        tailnetName: nil
    )
}

struct ManifestData: Codable, Equatable {
    let bundleId: String
    let version: String
    let title: String
    let ipaUrl: String
    let iconUrls: IconUrls
    
    struct IconUrls: Codable, Equatable {
        let small: String?
        let large: String?
    }
}