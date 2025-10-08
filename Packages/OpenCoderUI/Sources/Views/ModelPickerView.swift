import SwiftUI
import ComposableArchitecture
import OpenCoderCore

struct ModelPickerView: View {
  @Bindable var store: StoreOf<ChatFeature>

  var body: some View {
    Menu {
      if store.isLoadingProviders {
        Text("Loading...")
          .foregroundStyle(.secondary)
      } else if store.providers.isEmpty {
        Text("No providers available")
          .foregroundStyle(.secondary)
      } else {
        ForEach(store.providers) { provider in
          Menu {
            ForEach(provider.models) { model in
              Button(model.displayName) {
                store.send(.selectProvider(provider.id))
                store.send(.selectModel(model.id))
              }
            }
          } label: {
            Text(provider.name)
          }
        }
      }
    } label: {
      SettingsPickerLabel(
        title: "Provider & Model",
        displayText: displayText,
        isPlaceholder: store.currentModel == nil,
        isLoading: store.isLoadingProviders,
        iconName: "wand.and.sparkles"
      )
    }
    .disabled(store.isLoadingProviders || store.providers.isEmpty)
  }

  private var displayText: String {
    if let provider = store.currentProvider, let model = store.currentModel {
      return "\(provider.name) · \(model.displayName)"
    } else if let provider = store.currentProvider {
      return provider.name
    } else {
      return "Select Model"
    }
  }
}
