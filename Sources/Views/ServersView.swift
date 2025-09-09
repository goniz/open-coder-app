import ComposableArchitecture
import Features
import Models
import SwiftUI

struct ServersView: View {
  @Bindable var store: StoreOf<ServersFeature>
  var onStartTask: ((CodingTask) -> Void)?

  var body: some View {
    NavigationStack {
      VStack {
        if store.isLoading {
          ProgressView()
        } else if store.servers.isEmpty {
          emptyStateView
        } else {
          serversList
        }
      }
      .navigationTitle("Servers")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(action: { store.send(.addServer) }, label: {
            Image(systemName: "plus")
          })
        }
      }
      .sheet(isPresented: Binding(
        get: { store.isAddingServer },
        set: { if !$0 { store.send(.dismissAddServer) } }
      )) {
        AddServerView(onSave: { config in
          store.send(.addServerCompleted(config))
        }, onCancel: {
          store.send(.dismissAddServer)
        })
      }
    }
    .task {
      await store.send(.task).finish()
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 20) {
      Image(systemName: "server.rack")
        .font(.system(size: 64))
        .foregroundColor(.secondary)

      Text("No servers configured")
        .font(.title2)
        .foregroundColor(.secondary)

      Text("Add your first SSH server to get started")
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)

      Button(action: { store.send(.addServer) }, label: {
        Text("Add Server")
          .font(.headline)
          .foregroundColor(.white)
          .padding()
          .background(Color.accentColor)
          .cornerRadius(8)
      })
    }
    .padding()
  }

  private var serversList: some View {
    List {
      ForEach(store.servers) { server in
        ServerRowView(
          server: server,
          onTestConnection: { store.send(.testConnection(server.id)) },
          onDelete: { store.send(.removeServer(server.id)) },
          onStartTask: onStartTask
        )
      }
    }
  }
}

struct ServerRowView: View {
  let server: ServerState
  let onTestConnection: () -> Void
  let onDelete: () -> Void
  let onStartTask: ((CodingTask) -> Void)?

  @State private var showingTaskMenu = false

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(server.configuration.name.isEmpty ? server.configuration.host : server.configuration.name)
          .font(.headline)
        Text("\(server.configuration.username)@\(server.configuration.host):\(server.configuration.port)")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      Spacer()

      connectionStatusView

      if let onStartTask = onStartTask, server.connectionState == .connected {
        Button {
          showingTaskMenu = true
        } label: {
          Image(systemName: "play.fill")
            .foregroundColor(.green)
        }
        .confirmationDialog("Start Task", isPresented: $showingTaskMenu) {
          Button("Build") {
            onStartTask(CodingTask.mockBuildTask(serverID: server.id))
          }
          Button("Test") {
            onStartTask(CodingTask.mockTestTask(serverID: server.id))
          }
          Button("Deploy") {
            onStartTask(CodingTask.mockDeployTask(serverID: server.id))
          }
        }
      }

      Button(action: onTestConnection) {
        Image(systemName: "network")
          .foregroundColor(.accentColor)
      }
      .disabled(server.connectionState == .connecting)
    }
    .swipeActions {
      Button(role: .destructive, action: onDelete) {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  private var connectionStatusView: some View {
    HStack {
      switch server.connectionState {
      case .disconnected:
        Circle()
          .fill(Color.gray)
          .frame(width: 8, height: 8)
        Text("Disconnected")
          .font(.caption)
          .foregroundColor(.secondary)
      case .connecting:
        ProgressView()
          .scaleEffect(0.5)
        Text("Connecting...")
          .font(.caption)
          .foregroundColor(.secondary)
      case .connected:
        Circle()
          .fill(Color.green)
          .frame(width: 8, height: 8)
        Text("Connected")
          .font(.caption)
          .foregroundColor(.green)
      case .error:
        Circle()
          .fill(Color.red)
          .frame(width: 8, height: 8)
        Text("Error")
          .font(.caption)
          .foregroundColor(.red)
      }
    }
  }
}
