import Foundation

public struct ProvidersWithDefaults {
  public let providers: [Provider]
  public let defaultProviderID: String
  public let defaultModelID: String?

  public init(providers: [Provider], defaultProviderID: String, defaultModelID: String?) {
    self.providers = providers
    self.defaultProviderID = defaultProviderID
    self.defaultModelID = defaultModelID
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

    return ProvidersWithDefaults(
      providers: providers,
      defaultProviderID: openCodeProviders.defaultProvider,
      defaultModelID: openCodeProviders.defaultModel
    )
  }
}
