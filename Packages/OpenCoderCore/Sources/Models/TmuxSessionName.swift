import Foundation

public struct TmuxSessionName: Sendable, Codable, Equatable, Hashable, CustomStringConvertible {
  private static let prefix = "ocw-"

  public let workspaceComponent: String
  public let hashComponent: String
  public let sourcePath: String?
  private let rawValue: String

  public init(workspaceName: String, path: String) {
    let normalizedName = Self.normalizeWorkspaceName(workspaceName)
    let hash = Self.shortHash(for: path)
    self.workspaceComponent = normalizedName
    self.hashComponent = hash
    self.sourcePath = path
    self.rawValue = Self.composeName(component: normalizedName, hash: hash)
  }

  public init(rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized: (component: String, hash: String)

    if let parsed = Self.parse(rawValue: trimmed) {
      let component = Self.normalizeWorkspaceName(parsed.component)
      let hash = Self.normalizeHashComponent(parsed.hash)
      normalized = (component, hash)
    } else {
      let withoutPrefix =
        trimmed.hasPrefix(Self.prefix)
        ? String(trimmed.dropFirst(Self.prefix.count)) : trimmed
      let component = Self.normalizeWorkspaceName(withoutPrefix)
      let hash = Self.shortHash(for: trimmed)
      normalized = (component, hash)
    }

    self.workspaceComponent = normalized.component
    self.hashComponent = normalized.hash
    self.sourcePath = nil
    self.rawValue = Self.composeName(component: workspaceComponent, hash: hashComponent)
  }

  public var value: String { rawValue }

  public var description: String { rawValue }

  public func make() -> String { rawValue }

  public static func generate(workspaceName: String, path: String) -> String {
    TmuxSessionName(workspaceName: workspaceName, path: path).value
  }

  private static func composeName(component: String, hash: String) -> String {
    "\(prefix)\(component)-\(hash)"
  }

  private static func parse(rawValue: String) -> (component: String, hash: String)? {
    guard rawValue.hasPrefix(prefix) else { return nil }
    let remainder = rawValue.dropFirst(prefix.count)
    guard let separatorIndex = remainder.lastIndex(of: "-") else {
      return nil
    }

    let component = remainder[..<separatorIndex]
    let hash = remainder[remainder.index(after: separatorIndex)...]
    guard !component.isEmpty, hash.count == 8 else {
      return nil
    }
    return (String(component), String(hash))
  }

  private static func normalizeHashComponent(_ rawHash: String) -> String {
    let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
    var filtered = String()
    filtered.reserveCapacity(rawHash.count)

    for scalar in rawHash.lowercased().unicodeScalars {
      if hexChars.contains(scalar) {
        filtered.append(Character(scalar))
      }
      if filtered.count == 8 { break }
    }

    if filtered.isEmpty {
      return "00000000"
    }

    if filtered.count < 8 {
      filtered.append(String(repeating: "0", count: 8 - filtered.count))
    }

    return String(filtered.prefix(8))
  }

  private static func normalizeWorkspaceName(_ rawName: String) -> String {
    let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = trimmed.isEmpty ? "workspace" : trimmed
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    var sanitized = String()
    sanitized.reserveCapacity(candidate.count)

    var previousSeparator = false
    for scalar in candidate.unicodeScalars {
      if allowed.contains(scalar) {
        sanitized.append(Character(scalar))
        previousSeparator = false
      } else {
        if !previousSeparator {
          sanitized.append("_")
        }
        previousSeparator = true
      }
    }

    let trimmedSeparators = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    let base = trimmedSeparators.isEmpty ? "workspace" : trimmedSeparators
    let maxLength = 48
    return String(base.prefix(maxLength))
  }

  private static func shortHash(for path: String) -> String {
    let combined = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if combined.isEmpty {
      return "00000000"
    }

    var hash: UInt32 = 216_613_626_1
    for byte in combined.utf8 {
      hash ^= UInt32(byte)
      hash &*= 16_777_619
    }
    return String(format: "%08x", hash)
  }

  // MARK: Codable

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    self.init(rawValue: raw)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
