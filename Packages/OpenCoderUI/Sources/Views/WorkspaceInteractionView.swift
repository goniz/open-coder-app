import ComposableArchitecture
import OpenCoderCore
import SwiftUI

struct WorkspaceInteractionView: View {
  @Bindable var store: StoreOf<WorkspaceInteractionFeature>
  @State private var chatStore: StoreOf<ChatFeature>?
  @State private var hasInitialized = false

  init(store: StoreOf<WorkspaceInteractionFeature>) {
    self.store = store
  }

  var body: some View {
    WithViewStore(store, observe: { $0 }, content: { viewStore in
      content
        .onAppear {
          if !hasInitialized {
            chatStore = withDependencies {
              $0.openCodeAPIFactory = OpenCodeAPIClientFactory.live
            } operation: {
              Store(initialState: ChatFeature.State()) { ChatFeature() }
            }
            hasInitialized = true
            DispatchQueue.main.async {
              syncChat(state: viewStore.state)
            }
          }
        }
        .onChange(of: viewStore.openCodeServerURL) {
          syncChat(state: viewStore.state)
        }
        .onChange(of: viewStore.openCodeSessionID) {
          syncChat(state: viewStore.state)
        }
    })
  }

  private var content: some View {
    NavigationStack {
      VStack(spacing: 0) {
        header

        if case .spawning = store.onlineState {
          VStack(alignment: .leading, spacing: 4) {
            Text("Startup Status")
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundStyle(.secondary)
            ConnectionStatusStepsView(onlineState: store.onlineState)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .transition(.opacity)
        } else if case let .error(message) = store.onlineState, !message.isEmpty {
          WorkspaceInteractionErrorView(message: message) { store.send(.retryConnection) }
        }

        TabView(
          selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
          )
        ) {
          activityView
            .tabItem { Label("Activity", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(WorkspaceInteractionFeature.Tab.activity)

          LazyView {
            Group {
              if let chatStore = chatStore {
                ChatView(store: chatStore)
              } else {
                ProgressView("Loading chat...")
              }
            }
          }
          .tabItem { Label("Chat", systemImage: "message") }
          .tag(WorkspaceInteractionFeature.Tab.chat)

          terminalView
            .tabItem { Label("Terminal", systemImage: "terminal") }
            .tag(WorkspaceInteractionFeature.Tab.terminal)

          filesView
            .tabItem { Label("Files", systemImage: "folder") }
            .tag(WorkspaceInteractionFeature.Tab.files)

          WorkspaceLiveOutputTabView(workspace: store.workspace)
            .tabItem { Label("Live Output", systemImage: "text.alignleft") }
            .tag(WorkspaceInteractionFeature.Tab.liveOutput)
        }
      }
      .navigationTitle(store.workspace.name)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .task { await store.send(.task).finish() }
      .task(id: store.onlineState) { await store.send(.task).finish() }
    }
  }

  private func syncChat(state: WorkspaceInteractionFeature.State) {
    guard let chatStore = chatStore else { return }
    chatStore.send(.serverURLUpdated(state.openCodeServerURL))
    chatStore.send(.updateSession(state.openCodeSessionID))
    if state.openCodeServerURL != nil {
      chatStore.send(.fetchSessions)
    }
  }

  private var header: some View {
    HeaderView(
      workspace: store.workspace,
      serverConnection: store.serverConnection,
      onlineState: store.onlineState
    )
  }

  private var activityView: some View {
    ActivityTabView(store: store)
  }

  private var terminalView: some View {
    PlaceholderView(title: "Terminal", subtitle: "Interactive terminal coming soon", icon: "terminal")
  }

  private var filesView: some View {
    PlaceholderView(title: "Files", subtitle: "File browser coming soon", icon: "folder")
  }
}

struct HeaderView: View {
  let workspace: Workspace
  let serverConnection: ConnectionState
  let onlineState: WorkspaceOnlineState

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text("\(workspace.user)@\(workspace.host)")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(workspace.remotePath)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      Spacer()
      HStack(spacing: 4) {
        ServerBadgeView(state: serverConnection)
        StatusPillView(state: onlineState)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(.quaternary)
  }
}

struct ServerBadgeView: View {
  let state: ConnectionState

  var body: some View {
    let color: Color = {
      switch state {
      case .connected:
        return .green
      case .connecting:
        return .orange
      case .error:
        return .red
      case .disconnected:
        return .gray
      }
    }()

    let text = "SSH"

    return HStack(spacing: 3) {
      Circle().fill(color).frame(width: 5, height: 5)
      Text(text).font(.caption2)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(color.opacity(0.15))
    .cornerRadius(6)
  }
}

struct StatusPillView: View {
  let state: WorkspaceOnlineState

  var body: some View {
    let (color, text): (Color, String) = {
      switch state {
      case .idle:
        return (.gray, "Idle")
      case let .spawning(phase):
        return (.orange, phase.rawValue)
      case let .online(port):
        return (.green, "Online :\(port)")
      case let .error(message):
        let displayText = message.isEmpty ? "Error" : String(message.prefix(20)) + (message.count > 20 ? "..." : "")
        return (.red, displayText)
      }
    }()

    return HStack(spacing: 3) {
      Circle().fill(color).frame(width: 5, height: 5)
      Text(text).font(.caption2)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(color.opacity(0.15))
    .cornerRadius(6)
  }
}

struct WorkspaceInteractionErrorView: View {
  let message: String
  let onRetry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.red)
          .font(.title3)
        VStack(alignment: .leading) {
          Text("Connection Failed")
            .font(.headline)
            .foregroundColor(.red)
          Text(message)
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
        }
      }
      Button("Retry Connection") {
        onRetry()
      }
      .buttonStyle(.borderedProminent)
      .tint(.blue)
    }
    .padding()
    .background(Color.red.opacity(0.1))
    .cornerRadius(12)
    .padding()
    .transition(.opacity.combined(with: .scale))
  }
}

struct ActivityTabView: View {
  let store: StoreOf<WorkspaceInteractionFeature>

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if store.activityEvents.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
              .font(.title2)
              .foregroundColor(.secondary)
            Text("Activity")
              .font(.headline)
              .fontWeight(.medium)
            Text("Workspace activity will appear here")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        } else {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(store.activityEvents.reversed()) { event in
              ActivityEventRow(event: event)
              Divider()
            }
          }
        }

        RecentLogsView()
      }
    }
  }
}

struct PlaceholderView: View {
  let title: String
  let subtitle: String
  let icon: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.secondary)
      Text(title)
        .font(.headline)
        .fontWeight(.medium)
      Text(subtitle)
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

struct RecentLogsView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent Logs")
        .font(.headline)
        .padding(.top)
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(AppLogger.shared.recentLogs.prefix(10)), id: \.id) { log in
            HStack {
              Image(systemName: log.level.icon)
                .foregroundColor(log.level.color)
                .font(.caption)
              VStack(alignment: .leading) {
                Text(log.message)
                  .font(.caption)
                  .lineLimit(2)
                Text(log.timestamp, style: .time)
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
          }
        }
        .padding(.horizontal, 8)
      }
      .frame(height: 200)
      .background(Color.secondary.opacity(0.05))
      .cornerRadius(8)
    }
    .padding()
  }
}

struct ActivityEventRow: View {
  let event: ActivityEvent

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .center, spacing: 2) {
        Image(systemName: event.type.icon)
          .foregroundColor(event.isError ? .red : event.type.color)
          .font(.system(size: 14))
        Text(event.formattedTimestamp)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      .frame(width: 50)

      VStack(alignment: .leading, spacing: 2) {
        Text(event.type.rawValue)
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundColor(event.isError ? .red : .primary)
        Text(event.message)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

#Preview {
  WorkspaceInteractionView(
    store: .init(
      initialState: .init(
        workspace: Workspace(
          name: "Demo",
          host: "example.com",
          user: "dev",
          remotePath: "/home/dev/project"
        ),
        onlineState: .online(port: 8080),
        activityEvents: [
          ActivityEvent(
            type: .sshConnection,
            message: "SSH connection established successfully"
          ),
          ActivityEvent(
            type: .openCodeSpawn,
            message: "OpenCode workspace services are starting..."
          ),
          ActivityEvent(
            type: .portForwarding,
            message: "SSH port forwarding established on port 8080"
          ),
          ActivityEvent(
            type: .workspaceOnline,
            message: "Workspace is now online and ready on port 8080"
          )
        ]
      )
    ) { WorkspaceInteractionFeature() }
  )
}
