import ComposableArchitecture
import Features
import SwiftUI

struct SettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  var body: some View {
    Form {
      Section(header: Text("Appearance")) {
        Picker("Theme", selection: $store.theme) {
          ForEach(Theme.allCases, id: \.self) { theme in
            Text(theme.rawValue.capitalized)
          }
        }
      }

      Section(header: Text("Notifications")) {
        Toggle("Enable Notifications", isOn: $store.notificationsEnabled)
      }

      Section(header: Text("General")) {
        Toggle("Auto Save", isOn: $store.autoSaveEnabled)
        Button("Reset to Defaults") {
          store.send(.resetToDefaults)
        }
      }
    }
    .navigationTitle("Settings")
    .task {
      await store.send(.task).finish()
    }
  }
}