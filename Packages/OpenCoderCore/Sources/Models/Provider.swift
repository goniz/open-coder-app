import Foundation

public struct Provider: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let models: [Model]

  public init(id: String, name: String, models: [Model] = []) {
    self.id = id
    self.name = name
    self.models = models
  }
}

public struct Model: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let releaseDate: String?
  public let supportsAttachments: Bool
  public let supportsReasoning: Bool
  public let supportsToolCalls: Bool

  public init(
    id: String,
    name: String,
    releaseDate: String? = nil,
    supportsAttachments: Bool = false,
    supportsReasoning: Bool = false,
    supportsToolCalls: Bool = false
  ) {
    self.id = id
    self.name = name
    self.releaseDate = releaseDate
    self.supportsAttachments = supportsAttachments
    self.supportsReasoning = supportsReasoning
    self.supportsToolCalls = supportsToolCalls
  }

  public var displayName: String {
    return name.isEmpty ? id : name
  }
}
