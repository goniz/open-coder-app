import Foundation

enum OTAError: Error, LocalizedError {
    case noIPAFiles
    case invalidIPA
    case missingInfoPlist
    case certificateGenerationFailed
    case serverStartFailed
    case tailscaleNotAvailable
    case invalidPort
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .noIPAFiles:
            return "No IPA files found in current directory"
        case .invalidIPA:
            return "Invalid IPA file format"
        case .missingInfoPlist:
            return "Info.plist not found in IPA"
        case .certificateGenerationFailed:
            return "Failed to generate certificates"
        case .serverStartFailed:
            return "Failed to start HTTP server"
        case .tailscaleNotAvailable:
            return "Tailscale is not available or not running"
        case .invalidPort:
            return "Invalid port number"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}