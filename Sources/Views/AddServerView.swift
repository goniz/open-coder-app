import ComposableArchitecture
import Features
import Models
import SwiftUI

struct AddServerView: View {
  @State private var serverConfig = SSHServerConfiguration()
  @State private var showPassword = false
  let onSave: (SSHServerConfiguration) -> Void
  let onCancel: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text("Server Details")) {
          TextField("Server Name (optional)", text: $serverConfig.name)
            .textFieldStyle(.roundedBorder)

          TextField("Host", text: $serverConfig.host)
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)

          HStack {
            Text("Port")
            Spacer()
            TextField("Port", value: $serverConfig.port, format: .number)
              .textFieldStyle(.roundedBorder)
              .frame(width: 80)
              .multilineTextAlignment(.trailing)
          }

          TextField("Username", text: $serverConfig.username)
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)
        }

        Section(header: Text("Authentication")) {
          Toggle("Use SSH Key", isOn: $serverConfig.useKeyAuthentication)

          if serverConfig.useKeyAuthentication {
            TextField("Private Key Path", text: $serverConfig.privateKeyPath)
              .textFieldStyle(.roundedBorder)
              .disableAutocorrection(true)
          } else {
            HStack {
              if showPassword {
                TextField("Password", text: $serverConfig.password)
                  .textFieldStyle(.roundedBorder)
                  .disableAutocorrection(true)
              } else {
                SecureField("Password", text: $serverConfig.password)
                  .textFieldStyle(.roundedBorder)
              }

               Button(action: { showPassword.toggle() }, label: {
                 Image(systemName: showPassword ? "eye.slash" : "eye")
                   .foregroundColor(.secondary)
               })
            }
          }
        }
      }
      .navigationTitle("Add Server")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: {
            onSave(serverConfig)
          })
          .disabled(!serverConfig.isValid)
        }
      }
    }
  }
}
