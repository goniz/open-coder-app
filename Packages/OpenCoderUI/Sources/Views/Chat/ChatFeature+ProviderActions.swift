import ComposableArchitecture
import Models

extension ChatFeature {
  func handleProviderActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .fetchProviders:
      return handleFetchProviders(state: &state)

    case let .providersLoaded(providers, defaultProviderID, defaultModelID):
      return handleProvidersLoaded(
        state: &state,
        providers: providers,
        defaultProviderID: defaultProviderID,
        defaultModelID: defaultModelID
      )

    case let .providersFailed(error):
      state.isLoadingProviders = false
      state.errorMessage = "Failed to load providers: \(error)"
      return .none

    case let .selectProvider(providerID):
      state.selectedProviderID = providerID
      let provider = state.providers.first { $0.id == providerID }
      state.selectedModelID = provider?.models.first?.id
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
          defaultModelID: providersWithDefaults.defaultModelID
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
    defaultModelID: String?
  ) -> Effect<Action> {
    state.isLoadingProviders = false
    state.providers = providers

    validateAndUpdateSelections(
      state: &state,
      providers: providers,
      defaultProviderID: defaultProviderID,
      defaultModelID: defaultModelID
    )

    return .none
  }

  private func validateAndUpdateSelections(
    state: inout State,
    providers: [Provider],
    defaultProviderID: String,
    defaultModelID: String?
  ) {
    let currentProviderValid = state.selectedProviderID != nil &&
      providers.contains { $0.id == state.selectedProviderID }

    if !currentProviderValid {
      state.selectedProviderID = defaultProviderID
    }

    let currentModelValid = state.selectedModelID != nil &&
      state.currentProvider?.models.contains { $0.id == state.selectedModelID } ?? false

    if !currentModelValid {
      state.selectedModelID = selectDefaultModel(
        for: state.currentProvider,
        defaultModelID: defaultModelID
      )
    }
  }

  private func selectDefaultModel(
    for provider: Provider?,
    defaultModelID: String?
  ) -> String? {
    guard let provider = provider else { return nil }

    if let defaultModelID = defaultModelID,
       provider.models.contains(where: { $0.id == defaultModelID }) {
      return defaultModelID
    }

    return provider.models.first?.id
  }
}
