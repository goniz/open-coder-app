import ComposableArchitecture
import Models
import SwiftUI

struct AddWorkspaceView: View {
    let onSave: (Workspace) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var host = ""
    @State private var user = ""
    @State private var remotePath = ""
    @State private var idleTTLMinutes = 30

    @State private var showingServerSelection = false
    @State private var selectedServer: SSHServerConfiguration?

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace Information") {
                    TextField("Name", text: $name)
                        .textContentType(.name)

                    HStack {
                        TextField("Host", text: $host)
                            .textContentType(.URL)
                            .disabled(selectedServer != nil)

                        Button("Select Server") {
                            showingServerSelection = true
                        }
                        .buttonStyle(.bordered)
                    }

                    TextField("Username", text: $user)
                        .textContentType(.username)
                        .disabled(selectedServer != nil)

                    TextField("Remote Path", text: $remotePath)
                        .textContentType(.none)
                        .placeholder("/home/\(user)/projects/myproject")
                }

                Section("Configuration") {
                    Stepper("Idle TTL: \(idleTTLMinutes) minutes", value: $idleTTLMinutes, in: 5...120)

                    Text("Deterministic tmux session: \(generateTmuxSessionName())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    if let preview = sessionPreview {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview:")
                                .font(.headline)

                            HStack {
                                Text("Name:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(preview.name)
                                    .font(.caption)
                            }

                            HStack {
                                Text("Connection:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(preview.user)@\(preview.host):\(preview.remotePath)")
                                    .font(.caption)
                            }

                            HStack {
                                Text("Session:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(preview.tmuxSession)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Create Workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createWorkspace()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .sheet(isPresented: $showingServerSelection) {
            ServerSelectionView { server in
                selectedServer = server
                host = server.host
                user = server.username
                showingServerSelection = false
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sessionPreview: Workspace? {
        guard isValid else { return nil }
        return Workspace(
            name: name,
            host: host,
            user: user,
            remotePath: remotePath,
            idleTTLMinutes: idleTTLMinutes
        )
    }

    private func generateTmuxSessionName() -> String {
        guard !user.isEmpty && !host.isEmpty && !remotePath.isEmpty else {
            return "ocw-user-host-hash"
        }
        return Workspace.generateTmuxSessionName(user: user, host: host, path: remotePath)
    }

    private func createWorkspace() {
        guard isValid else { return }

        let workspace = Workspace(
            name: name,
            host: host,
            user: user,
            remotePath: remotePath,
            idleTTLMinutes: idleTTLMinutes
        )

        onSave(workspace)
    }
}

struct ServerSelectionView: View {
    let onSelect: (SSHServerConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var servers: [SSHServerConfiguration] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if servers.isEmpty {
                    emptyStateView
                } else {
                    serversList
                }
            }
            .navigationTitle("Select Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadServers()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No servers available")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Add a server first in the Servers tab")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var serversList: some View {
        List(servers, id: \.self) { server in
            Button(
                action: {
                    onSelect(server)
                },
                label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name.isEmpty ? server.host : server.name)
                            .font(.headline)

                        Text("\(server.username)@\(server.host):\(server.port)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            )
            }
        }
    }

    private func loadServers() async {
        // Load from storage - similar to ServersFeature
        guard let data = UserDefaults.standard.data(forKey: "savedServers") else {
            isLoading = false
            return
        }

        do {
            let configurations = try JSONDecoder().decode([SSHServerConfiguration].self, from: data)
            servers = configurations
            isLoading = false
        } catch {
            print("Failed to load servers: \(error)")
            isLoading = false
        }
    }
}

#Preview {
    AddWorkspaceView(onSave: { _ in }, onCancel: {})
}

extension View {
    func placeholder(_ text: String) -> some View {
        self.modifier(PlaceholderModifier(text: text))
    }
}

struct PlaceholderModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                // macOS text fields handle placeholders automatically
                // This overlay is kept for consistency but simplified
                EmptyView()
            }
    }
}
