import Foundation

public struct ProvidersWithDefaults {
  public let providers: [Provider]
  public let defaultProviderID: String
  public let defaultModelIDsByProvider: [String: String]

  public init(
    providers: [Provider],
    defaultProviderID: String,
    defaultModelIDsByProvider: [String: String] = [:]
  ) {
    self.providers = providers
    self.defaultProviderID = defaultProviderID
    self.defaultModelIDsByProvider = defaultModelIDsByProvider
  }

  public func defaultModelID(for providerID: String) -> String? {
    defaultModelIDsByProvider[providerID]
  }

  public var defaultModelID: String? {
    defaultModelID(for: defaultProviderID)
  }
}

extension ProvidersWithDefaults {
  public static func from(openCodeProviders: OpenCodeProviders) -> ProvidersWithDefaults {
    let providers = openCodeProviders.providers.map { (providerID, providerInfo) in
      let models = providerInfo.models.map { (modelID, modelName) in
        Model(
          id: modelID,
          name: modelName.isEmpty ? modelID : modelName
        )
      }.sorted { $0.displayName < $1.displayName }

      return Provider(
        id: providerID,
        name: providerInfo.name,
        models: models
      )
    }.sorted { $0.name < $1.name }

    let primaryDefaultProviderID = openCodeProviders.primaryDefaultProviderID
      ?? providers.first?.id
      ?? openCodeProviders.providers.keys.sorted().first
      ?? ""

    var defaultModelsByProvider = openCodeProviders.defaultModelsByProvider

    if let primaryDefaultModelID = openCodeProviders.primaryDefaultModelID,
       !primaryDefaultModelID.isEmpty,
       defaultModelsByProvider[primaryDefaultProviderID] == nil {
      defaultModelsByProvider[primaryDefaultProviderID] = primaryDefaultModelID
    }

    return ProvidersWithDefaults(
      providers: providers,
      defaultProviderID: primaryDefaultProviderID,
      defaultModelIDsByProvider: defaultModelsByProvider
    )
  }
}
