import SwiftUI
import ComposableArchitecture
import OpenCoderCore

struct ModelPickerView: View {
  @Bindable var store: StoreOf<ChatFeature>

  var body: some View {
    HStack(spacing: 8) {
      providerPicker
      modelPicker
    }
  }

  private var providerPicker: some View {
    Menu {
      if store.isLoadingProviders {
        Text("Loading...")
          .foregroundStyle(.secondary)
      } else if store.providers.isEmpty {
        Text("No providers available")
          .foregroundStyle(.secondary)
      } else {
        ForEach(store.providers) { provider in
          Button(provider.name) {
            store.send(.selectProvider(provider.id))
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        if store.isLoadingProviders {
          ProgressView()
            .scaleEffect(0.7)
        }

        Text(store.currentProvider?.name ?? "Provider")
          .font(.caption)
          .fontWeight(.medium)

        Image(systemName: "chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color(.systemGray6))
      .cornerRadius(6)
    }
    .disabled(store.isLoadingProviders || store.providers.isEmpty)
  }

  private var modelPicker: some View {
    Menu {
      if store.availableModels.isEmpty {
        Text("No models available")
          .foregroundStyle(.secondary)
      } else {
        ForEach(store.availableModels) { model in
          Button(model.displayName) {
            store.send(.selectModel(model.id))
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text(store.currentModel?.displayName ?? "Model")
          .font(.caption)
          .fontWeight(.medium)

        Image(systemName: "chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color(.systemGray6))
      .cornerRadius(6)
    }
    .disabled(store.availableModels.isEmpty)
  }
}
