import ComposableArchitecture
import OpenCoderCore
import SwiftUI

struct WorkspaceInteractionView: View {
  @Bindable var store: StoreOf<WorkspaceInteractionFeature>
  @State private var chatStore: StoreOf<ChatFeature>?
  @State private var hasInitialized = false
  let settings: SettingsFeature.State

  init(store: StoreOf<WorkspaceInteractionFeature>, settings: SettingsFeature.State) {
    self.store = store
    self.settings = settings
  }

  var body: some View {
    WithViewStore(store, observe: { $0 }, content: { viewStore in
      content
        .onAppear {
          if !hasInitialized {
             let weakStore = store
             chatStore = withDependencies {
                $0.openCodeAPIFactory = OpenCodeAPIClientFactory.live
                $0.sessionUpdateClient = SessionUpdateClient { session in
                  Task { @MainActor in
                    weakStore.send(.sessionUpdated(session))
                  }
                }
              } operation: {
                Store(
                  initialState: ChatFeature.State(thinkingBlocksEnabled: settings.thinkingBlocksEnabled)
                ) { ChatFeature() }
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
      .environment(\.workspaceRemotePath, store.workspace.remotePath)
      .navigationTitle(store.displayTitle)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            store.send(.dismiss)
          } label: {
            Image(systemName: "xmark")
          }
        }

        ToolbarItem(placement: .primaryAction) {
          if case .online = store.onlineState {
            Button {
              store.send(.reloadServer)
            } label: {
              Label("Reload Server", systemImage: "arrow.clockwise")
            }
          }
        }
      }
      .task { await store.send(.task).finish() }
      .task(id: store.onlineState) { await store.send(.task).finish() }
    }
  }

  private func syncChat(state: WorkspaceInteractionFeature.State) {
    guard let chatStore = chatStore else { return }
    chatStore.send(.serverURLUpdated(state.openCodeServerURL))
    chatStore.send(.updateSession(state.openCodeSessionID))
    chatStore.send(.workspaceDisplayTitleUpdated(state.displayTitle))
    if state.openCodeServerURL != nil {
      chatStore.send(.fetchSessions)
    }
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

        LiveLogsView()
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

struct LiveLogsView: View {
  @ObservedObject private var logger = AppLogger.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Live Logs")
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.top, 12)

      if logger.logEntries.isEmpty {
        Text("No logs yet")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .padding(.horizontal, 12)
          .padding(.bottom, 12)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(logger.logEntries) { log in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: log.level.icon)
                  .foregroundColor(log.level.color)
                  .font(.caption)
                  .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                  HStack {
                    Text(log.category.rawValue)
                      .font(.caption2)
                      .foregroundColor(.secondary)
                      .padding(.horizontal, 4)
                      .padding(.vertical, 2)
                      .background(Color.secondary.opacity(0.1))
                      .cornerRadius(4)

                    Text(log.formattedTimestamp)
                      .font(.caption2)
                      .foregroundColor(.secondary)

                    Spacer()
                  }

                  Text(log.message)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
            }
          }
          .padding(.horizontal, 4)
        }
        .frame(maxHeight: 300)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
      }
    }
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
    ) { WorkspaceInteractionFeature() },
    settings: .init()
  )
}
