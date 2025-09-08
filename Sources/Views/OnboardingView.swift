import ComposableArchitecture
import Features
import SwiftUI

struct OnboardingView: View {
  @Bindable var store: StoreOf<OnboardingFeature>

  init(store: StoreOf<OnboardingFeature>) {
    self.store = store
  }

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          headerSection

          serverConfigurationForm

          actionButtons
        }
        .padding(24)
      }
      .navigationTitle("Welcome to OpenCoder")
    }
  }

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: "terminal.fill")
        .font(.system(size: 48))
        .foregroundColor(.accentColor)

      Text("Connect to your server")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Configure your first SSH server connection to get started coding remotely.")
        .font(.body)
        .foregroundColor(.secondary)
    }
  }

  private var serverConfigurationForm: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Server Configuration")
        .font(.headline)

      VStack(spacing: 12) {
        TextField("Server Name", text: $store.serverConfiguration.name)
          .textFieldStyle(.roundedBorder)

        TextField("Host", text: $store.serverConfiguration.host)
          .textFieldStyle(.roundedBorder)
          .disableAutocorrection(true)

        HStack {
          TextField("Port", value: $store.serverConfiguration.port, format: .number)
            .textFieldStyle(.roundedBorder)

          Spacer()
        }

        TextField("Username", text: $store.serverConfiguration.username)
          .textFieldStyle(.roundedBorder)
          .disableAutocorrection(true)

        authenticationSection
      }

      if let error = store.connectionError {
        Text(error)
          .foregroundColor(.red)
          .font(.caption)
      }
    }
  }

  private var authenticationSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Authentication Method")
          .font(.subheadline)
          .fontWeight(.medium)

        Spacer()

        Button(
          action: { store.send(.toggleAuthenticationMethod) },
          label: {
            Text(store.serverConfiguration.useKeyAuthentication ? "SSH Key" : "Password")
              .font(.caption)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.accentColor.opacity(0.1))
              .foregroundColor(.accentColor)
              .cornerRadius(4)
          }
        )

      if store.serverConfiguration.useKeyAuthentication {
        TextField("Private Key Path", text: $store.serverConfiguration.privateKeyPath)
          .textFieldStyle(.roundedBorder)
          .disableAutocorrection(true)
      } else {
        HStack {
          if store.showPassword {
            TextField("Password", text: $store.serverConfiguration.password)
              .textFieldStyle(.roundedBorder)
              .disableAutocorrection(true)
          } else {
            SecureField("Password", text: $store.serverConfiguration.password)
              .textFieldStyle(.roundedBorder)
          }

          Button(
            action: { store.send(.togglePasswordVisibility) },
            label: {
              Image(systemName: store.showPassword ? "eye.slash" : "eye")
                .foregroundColor(.secondary)
            }
          )
        }
      }
    }
  }
  }

  private var actionButtons: some View {
    VStack(spacing: 12) {
      Button(
        action: { store.send(.connectButtonTapped) },
        label: {
          HStack {
            if store.isConnecting {
              ProgressView()
                .scaleEffect(0.8)
                .tint(.white)
            } else {
              Image(systemName: "network")
            }

            Text(store.isConnecting ? "Connecting..." : "Test Connection")
          }
          .font(.headline)
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 50)
          .background(
            store.serverConfiguration.isValid && !store.isConnecting
              ? Color.accentColor
              : Color.gray
          )
          .cornerRadius(8)
        }
      )

      Button(
        action: { store.send(.skipOnboarding) },
        label: {
          Text("Skip for now")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      )
    }
  }
}

#Preview {
  OnboardingView(
    store: .init(
      initialState: .init(),
      reducer: {
        OnboardingFeature()
      }
    )
  )
}
