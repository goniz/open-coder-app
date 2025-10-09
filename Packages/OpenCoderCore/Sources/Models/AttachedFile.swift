import Foundation

public struct AttachedFile: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let path: String
    public let content: Data?
    public let metadata: [String: String] // e.g., size, mimeType
    public var startIndex: Int?
    public var endIndex: Int?

    public init(
        path: String,
        content: Data?,
        metadata: [String: String] = [:],
        startIndex: Int? = nil,
        endIndex: Int? = nil
    ) {
        self.path = path
        self.content = content
        self.metadata = metadata
        self.startIndex = startIndex
        self.endIndex = endIndex
    }

    public var displayPath: String {
        "@\(path)"
    }

    public var displayName: String {
        if let mimeType = metadata["mimeType"], mimeType.hasPrefix("image/") {
            return "[Image]"
        }
        return displayPath
    }

    public var mimeType: String {
        return metadata["mimeType"] ?? "text/plain"
    }

    public var isImage: Bool {
        return mimeType.hasPrefix("image/")
    }
}
