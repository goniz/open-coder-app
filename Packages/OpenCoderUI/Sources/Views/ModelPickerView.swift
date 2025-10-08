import SwiftUI
import UIKit
import ComposableArchitecture
import OpenCoderCore

struct ModelPickerView: View {
  @Bindable var store: StoreOf<ChatFeature>
  @Binding var isExpanded: Bool
  @State private var selectedProviderID: String?

  var body: some View {
    SettingsDropdown(
      isExpanded: $isExpanded,
      isDisabled: store.isLoadingProviders || store.providers.isEmpty
    ) {
      SettingsPickerLabel(
        title: "Provider & Model",
        displayText: displayText,
        isPlaceholder: store.currentModel == nil,
        isLoading: store.isLoadingProviders,
        iconName: "wand.and.sparkles",
        isActive: isExpanded
      )
    } content: { dismiss in
      ModelPickerMenuContent(
        store: store,
        selectedProviderID: selectedProviderBinding,
        dismiss: dismiss
      )
    }
    .onChange(of: store.currentProvider?.id) { _, newValue in
      selectedProviderID = newValue
    }
    .onChange(of: store.providers) { _, providers in
      guard !providers.isEmpty else {
        selectedProviderID = nil
        return
      }

      if let selectedProviderID,
         providers.contains(where: { $0.id == selectedProviderID }) {
        return
      }

      selectedProviderID = store.currentProvider?.id ?? providers.first?.id
    }
    .onChange(of: isExpanded) { _, isExpanded in
      if isExpanded {
        // Dismiss keyboard when dropdown expands
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        selectedProviderID = store.currentProvider?.id ?? selectedProviderID ?? store.providers.first?.id
      }
    }
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

  private var selectedProviderBinding: Binding<String?> {
    Binding(
      get: {
        if let id = selectedProviderID {
          return id
        }
        if let currentProvider = store.currentProvider {
          return currentProvider.id
        }
        return store.providers.first?.id
      },
      set: { newValue in
        selectedProviderID = newValue
      }
    )
  }
}

private struct ModelPickerMenuContent: View {
  @Bindable var store: StoreOf<ChatFeature>
  @Binding var selectedProviderID: String?
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      menuBody
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 12)
  }

  @ViewBuilder
  private var menuBody: some View {
    if store.isLoadingProviders {
      loadingView
    } else if store.providers.isEmpty {
      emptyView
    } else {
      providersList
    }
  }

  private var loadingView: some View {
    HStack(spacing: 10) {
      ProgressView()
      Text("Loading providers…")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var emptyView: some View {
    Text("No providers available")
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var providersList: some View {
    let activeProvider = store.providers.first { $0.id == selectedProviderID } ?? store.providers.first

    return HStack(alignment: .top, spacing: 12) {
      providerColumn
        .frame(width: 160, alignment: .leading)

      Divider()

      if let activeProvider {
        modelsColumn(for: activeProvider)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text("Select a provider")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(maxHeight: 300)
  }

  private var providerColumn: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(store.providers) { provider in
          let isSelected = (selectedProviderID ?? store.currentProvider?.id ?? store.providers.first?.id) == provider.id

          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              selectedProviderID = provider.id
            }
          } label: {
            HStack {
              Text(provider.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
              Spacer(minLength: 0)
              if isSelected {
                Image(systemName: "checkmark")
                  .font(.footnote.weight(.semibold))
                  .foregroundStyle(Color.accentColor)
              }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                  isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(.systemGray6)
                )
            )
          }
          .buttonStyle(.plain)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func modelsColumn(for provider: Provider) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text(provider.name.uppercased())
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ForEach(provider.models) { model in
          providerModelButton(providerID: provider.id, model: model)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func providerModelButton(providerID: String, model: Model) -> some View {
    Button {
      store.send(.selectProvider(providerID))
      store.send(.selectModel(model.id))
      dismiss()
    } label: {
      HStack {
        Text(model.displayName)
          .foregroundStyle(.primary)
        Spacer(minLength: 0)
        if store.currentModel?.id == model.id {
          Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
        }
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(.systemGray6))
      )
    }
    .buttonStyle(.plain)
  }
}
