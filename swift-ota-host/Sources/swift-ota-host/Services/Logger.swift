import Foundation

struct Logger {
    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
    
    static func info(_ message: String) {
        print("[\(timestamp())] INFO: \(message)")
    }
    
    static func warn(_ message: String) {
        print("[\(timestamp())] WARN: \(message)")
    }
    
    static func error(_ message: String) {
        print("[\(timestamp())] ERROR: \(message)")
    }
    
    static func debug(_ message: String) {
        print("[\(timestamp())] DEBUG: \(message)")
    }
}