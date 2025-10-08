import Foundation

public struct OpenCodeProviderInfo: Equatable, Sendable {
  public let name: String
  public let models: [String: String]

  public init(name: String, models: [String: String]) {
    self.name = name
    self.models = models
  }
}

public struct OpenCodeProviders: Equatable, Sendable {
  public let providers: [String: OpenCodeProviderInfo]
  public let defaultProvider: String
  public let defaultModel: String?

  public init(providers: [String: OpenCodeProviderInfo], defaultProvider: String, defaultModel: String? = nil) {
    self.providers = providers
    self.defaultProvider = defaultProvider
    self.defaultModel = defaultModel
  }
}
