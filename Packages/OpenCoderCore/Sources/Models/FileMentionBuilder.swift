import Foundation

public enum FileMentionBuilder {
  public struct FileTokenMatch: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let token: String
  }
  /// Merge file references into the given text without duplicating existing mentions.
  /// - Parameters:
  ///   - text: The user-authored text.
  ///   - attachedFiles: Files attached to the draft.
  /// - Returns: A text where only missing file mentions are prepended.
  public static func mergedText(_ text: String, with attachedFiles: [AttachedFile]) -> String {
    guard !attachedFiles.isEmpty else { return text }

    var missing: [String] = []
    for file in attachedFiles {
      let pathToken = file.displayPath
      let nameToken = file.displayName
      if text.contains(pathToken) || text.contains(nameToken) {
        continue
      }
      missing.append(nameToken)
    }

    guard !missing.isEmpty else { return text }
    let prefix = missing.joined(separator: " ")
    return text.isEmpty ? prefix : "\(prefix) \(text)"
  }

  /// Find the next token occurrence in `text` for the provided `file`, starting from the
  /// given UTF-16 offset. Prefers an explicit path mention ("@path") and falls back
  /// to the display name (e.g. "[Image]") if needed.
  /// - Returns: start/end UTF-16 indices and the concrete token string that was found, or nil if not found.
  public static func nextToken(
    in text: String,
    for file: AttachedFile,
    startFrom: Int
  ) -> FileTokenMatch? {
    let startIndex = text.index(text.startIndex, offsetBy: max(0, startFrom))
    let searchRange = startIndex..<text.endIndex

    let pathToken = file.displayPath
    if let range = text.range(of: pathToken, range: searchRange) {
      let startUTF16 = range.lowerBound.utf16Offset(in: text)
      return FileTokenMatch(start: startUTF16, end: startUTF16 + pathToken.utf16.count, token: pathToken)
    }

    let nameToken = file.displayName
    if let range = text.range(of: nameToken, range: searchRange) {
      let startUTF16 = range.lowerBound.utf16Offset(in: text)
      return FileTokenMatch(start: startUTF16, end: startUTF16 + nameToken.utf16.count, token: nameToken)
    }

    return nil
  }
}
