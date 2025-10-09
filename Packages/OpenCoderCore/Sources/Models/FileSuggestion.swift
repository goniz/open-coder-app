import Foundation

public struct FileSuggestion: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let path: String
    public let name: String
    public let type: String? // e.g., "swift", "txt"

    public init(path: String, name: String, type: String?) {
        self.path = path
        self.name = name
        self.type = type
    }
}
