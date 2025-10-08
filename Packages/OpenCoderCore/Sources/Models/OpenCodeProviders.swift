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
  public let defaultModelsByProvider: [String: String]
  public let primaryDefaultProviderID: String?
  public let primaryDefaultModelID: String?

  public init(
    providers: [String: OpenCodeProviderInfo],
    defaultModelsByProvider: [String: String] = [:],
    primaryDefaultProviderID: String? = nil,
    primaryDefaultModelID: String? = nil
  ) {
    self.providers = providers
    self.defaultModelsByProvider = defaultModelsByProvider
    self.primaryDefaultProviderID = primaryDefaultProviderID
    self.primaryDefaultModelID = primaryDefaultModelID
  }

  public func defaultModelID(for providerID: String) -> String? {
    defaultModelsByProvider[providerID]
  }
}
