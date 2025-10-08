import ComposableArchitecture
import Models

extension ChatFeature {
  func handleProviderActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .fetchProviders:
      return handleFetchProviders(state: &state)

    case let .providersLoaded(providers, defaultProviderID, defaultModelIDsByProvider):
      return handleProvidersLoaded(
        state: &state,
        providers: providers,
        defaultProviderID: defaultProviderID,
        defaultModelIDsByProvider: defaultModelIDsByProvider
      )

    case let .providersFailed(error):
      state.isLoadingProviders = false
      state.errorMessage = "Failed to load providers: \(error)"
      return .none

    case let .selectProvider(providerID):
      state.selectedProviderID = providerID
      let provider = state.providers.first { $0.id == providerID }
      state.selectedModelID = selectDefaultModel(
        for: provider,
        defaultModelIDsByProvider: state.defaultModelIDsByProvider
      )
      return .none

    case let .selectModel(modelID):
      state.selectedModelID = modelID
      return .none

    default:
      return .none
    }
  }

  private func handleFetchProviders(state: inout State) -> Effect<Action> {
    guard !state.isLoadingProviders, let serverURL = state.serverURL else {
      return .none
    }

    state.isLoadingProviders = true
    let factory = self.openCodeAPIFactory

    return .run { send in
      do {
        let client = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let openCodeProviders = try await client.listProviders()
        let providersWithDefaults = ProvidersWithDefaults.from(openCodeProviders: openCodeProviders)
        await send(.providersLoaded(
          providersWithDefaults.providers,
          defaultProviderID: providersWithDefaults.defaultProviderID,
          defaultModelIDsByProvider: providersWithDefaults.defaultModelIDsByProvider
        ))
      } catch {
        await send(.providersFailed(error.localizedDescription))
      }
    }
  }

  private func handleProvidersLoaded(
    state: inout State,
    providers: [Provider],
    defaultProviderID: String,
    defaultModelIDsByProvider: [String: String]
  ) -> Effect<Action> {
    state.isLoadingProviders = false
    state.providers = providers
    state.defaultModelIDsByProvider = defaultModelIDsByProvider

    validateAndUpdateSelections(
      state: &state,
      providers: providers,
      defaultProviderID: defaultProviderID,
      defaultModelIDsByProvider: defaultModelIDsByProvider
    )

    return .none
  }

  private func validateAndUpdateSelections(
    state: inout State,
    providers: [Provider],
    defaultProviderID: String,
    defaultModelIDsByProvider: [String: String]
  ) {
    let currentProviderValid = state.selectedProviderID != nil &&
      providers.contains { $0.id == state.selectedProviderID }

    if !currentProviderValid {
      let resolvedDefaultProviderID = defaultProviderID.isEmpty
        ? providers.first?.id
        : defaultProviderID
      state.selectedProviderID = resolvedDefaultProviderID
    }

    let currentModelValid = state.selectedModelID != nil &&
      state.currentProvider?.models.contains { $0.id == state.selectedModelID } ?? false

    if !currentModelValid {
      state.selectedModelID = selectDefaultModel(
        for: state.currentProvider,
        defaultModelIDsByProvider: defaultModelIDsByProvider
      )
    }
  }

  private func selectDefaultModel(
    for provider: Provider?,
    defaultModelIDsByProvider: [String: String]
  ) -> String? {
    guard let provider = provider else { return nil }

    if let defaultModelID = defaultModelIDsByProvider[provider.id],
       provider.models.contains(where: { $0.id == defaultModelID }) {
      return defaultModelID
    }

    return provider.models.first?.id
  }
}
