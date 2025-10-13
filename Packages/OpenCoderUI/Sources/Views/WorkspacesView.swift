import ComposableArchitecture
 import OpenCoderCore
 import SwiftUI

struct WorkspacesView: View {
  @Bindable var store: StoreOf<WorkspacesFeature>

  var body: some View {
    NavigationStack {
      VStack {
        if store.isLoading {
          ProgressView()
        } else if store.workspaces.isEmpty {
          emptyStateView
        } else {
          workspacesList
        }
      }
      .navigationTitle("Workspaces")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(
            action: { store.send(.addWorkspace) },
            label: {
              Image(systemName: "plus")
            })
        }
      }
      .sheet(
        isPresented: Binding(
          get: { store.isAddingWorkspace },
          set: { if !$0 { store.send(.dismissAddWorkspace) } }
        )
      ) {
        AddWorkspaceView(
          onSave: { workspace in
            store.send(.addWorkspaceCompleted(workspace))
          },
          onCancel: {
            store.send(.dismissAddWorkspace)
          })
      }
      .fullScreenCover(
        isPresented: Binding(
          get: { store.showingWorkspaceInteraction && store.workspaceInteraction != nil },
          set: { if !$0 { store.send(.hideWorkspaceInteraction) } }
        )
      ) {
        if let interactionStore = store.scope(
          state: \.workspaceInteraction,
          action: \.workspaceInteraction
        ) {
          WorkspaceInteractionView(store: interactionStore, settings: store.settings)
            .interactiveDismissDisabled(true)
        }
      }
    }
    .task {
      await store.send(.task).finish()
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 20) {
      Image(systemName: "folder.badge.plus")
        .font(.system(size: 64))
        .foregroundColor(.secondary)

      Text("No workspaces configured")
        .font(.title2)
        .foregroundColor(.secondary)

      Text("Create your first workspace to get started")
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)

      Button(
        action: { store.send(.addWorkspace) },
        label: {
          Text("Create Workspace")
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(Color.accentColor)
            .cornerRadius(8)
        })
    }
    .padding()
  }

  private var workspacesList: some View {
    List {
      ForEach(store.workspaces) { workspaceState in
        WorkspaceRowView(
          workspaceState: workspaceState,
          onOpen: { store.send(.openWorkspace(workspaceState.id)) },
          onRefresh: { store.send(.refreshWorkspace(workspaceState.id)) },
          onDelete: { store.send(.removeWorkspace(workspaceState.id)) },
          onShowLiveOutput: { store.send(.showLiveOutput(workspaceState.id)) },
          onCleanAndRetry: { store.send(.cleanAndRetry(workspaceState.id)) },
          onReloadServer: { store.send(.reloadServer(workspaceState.id)) }
        )
      }
    }
    .refreshable {
      await refreshAllWorkspaces()
    }
  }

  private func refreshAllWorkspaces() async {
    for workspace in store.workspaces {
      if case .online = workspace.onlineState {
        await store.send(.refreshWorkspace(workspace.id)).finish()
      }
    }
  }
}

struct WorkspaceRowView: View {
  let workspaceState: WorkspacesFeature.WorkspaceState
  let onOpen: () -> Void
  let onRefresh: () -> Void
  let onDelete: () -> Void
  let onShowLiveOutput: () -> Void
  let onCleanAndRetry: () -> Void
  let onReloadServer: () -> Void

  private var serverName: String {
    guard let serverID = workspaceState.workspace.serverID else {
      return workspaceState.workspace.host
    }

    guard let data = UserDefaults.standard.data(forKey: "savedServers"),
          let configurations = try? JSONDecoder().decode([SSHServerConfiguration].self, from: data),
          let server = configurations.first(where: { $0.id == serverID }) else {
      return workspaceState.workspace.host
    }

    return server.name
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(workspaceState.workspace.name) via \(serverName)")
            .font(.headline)

          Text(workspaceState.workspace.remotePath)
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        Spacer()

        statePill
      }

      if !workspaceState.sessions.isEmpty {
        sessionsPreview
      }

      if case .spawning = workspaceState.onlineState {
        ConnectionStatusStepsView(
          onlineState: workspaceState.onlineState,
          presentation: .inline
        )
        .padding(.top, 8)
      }

      if case .error(let errorMessage) = workspaceState.onlineState {
        errorMessageView(errorMessage)
      }

      actionButtons
    }
    .padding(.vertical, 8)
    .swipeActions {
      Button(role: .destructive, action: onDelete) {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  private var statePill: some View {
    HStack(spacing: 4) {
      switch workspaceState.onlineState {
      case .idle:
        Circle()
          .fill(Color.gray)
          .frame(width: 6, height: 6)
        Text("Idle")
          .font(.caption2)
          .foregroundColor(.secondary)

      case .spawning(let phase):
        ProgressView()
          .scaleEffect(0.5)
        Text(phase.rawValue)
          .font(.caption2)
          .foregroundColor(.orange)

      case .online:
        Circle()
          .fill(Color.green)
          .frame(width: 6, height: 6)
        Text("Online")
          .font(.caption2)
          .foregroundColor(.green)

      case .error:
        Circle()
          .fill(Color.red)
          .frame(width: 6, height: 6)
        Text("Error")
          .font(.caption2)
          .foregroundColor(.red)
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(8)
  }

  private var sessionsPreview: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Recent Sessions:")
        .font(.caption)
        .foregroundColor(.secondary)

      ForEach(workspaceState.sessions.prefix(2), id: \.id) { session in
        HStack {
          Text(session.title)
            .font(.caption)
            .lineLimit(1)

          Spacer()

          Text(formattedDate(session.updatedAt))
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }

      if workspaceState.sessions.count > 2 {
        Text("+\(workspaceState.sessions.count - 2) more")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  private var actionButtons: some View {
    HStack(spacing: 12) {
      switch workspaceState.onlineState {
      case .idle:
        Button(action: onOpen) {
          Label("Connect", systemImage: "arrow.right.circle")
            .font(.caption)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)

      case .spawning:
        ProgressView()
          .scaleEffect(0.8)

      case .online:
        Button(action: onShowLiveOutput) {
          Label("Open", systemImage: "arrow.right.circle")
            .font(.caption)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)

        Button(action: onRefresh) {
          Image(systemName: "arrow.clockwise")
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .disabled(workspaceState.isRefreshing)

        Menu {
          Button(action: onReloadServer) {
            Label("Reload Server", systemImage: "arrow.clockwise.circle")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.caption)
        }
        .buttonStyle(.bordered)

      case .error:
        Button(action: onCleanAndRetry) {
          Label("Retry", systemImage: "arrow.clockwise")
            .font(.caption)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
      }
    }
  }

  private func formattedDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func errorMessageView(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.red)
          .font(.caption)
        Text("Error Details:")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(.red)
      }

      Text(message)
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(Color.red.opacity(0.1))
    .cornerRadius(8)
  }
}

#Preview {
  WorkspacesView(
    store: .init(
      initialState: .init()
    ) {
        WorkspacesFeature()
      }
  )
}
