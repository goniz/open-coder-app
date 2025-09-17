import ComposableArchitecture
import Features
import Models
import SwiftUI

struct WorkspaceInteractionView: View {
  @Bindable var store: StoreOf<WorkspaceInteractionFeature>

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        header

        TabView(
          selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
          )
        ) {
          WorkspaceLiveOutputTabView(workspace: store.workspace)
            .tabItem { Label("Live Output", systemImage: "text.alignleft") }
            .tag(WorkspaceInteractionFeature.Tab.liveOutput)

          activityView
            .tabItem { Label("Activity", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(WorkspaceInteractionFeature.Tab.activity)

          ChatView(store: store.scope(state: \.chat, action: \.chat))
            .tabItem { Label("Chat", systemImage: "message") }
            .tag(WorkspaceInteractionFeature.Tab.chat)

          terminalView
            .tabItem { Label("Terminal", systemImage: "terminal") }
            .tag(WorkspaceInteractionFeature.Tab.terminal)

          filesView
            .tabItem { Label("Files", systemImage: "folder") }
            .tag(WorkspaceInteractionFeature.Tab.files)
        }
      }
      .navigationTitle(store.workspace.name)
      .task { await store.send(.task).finish() }
      .task(id: store.onlineState) { await store.send(.task).finish() }
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(store.workspace.user)@\(store.workspace.host)")
          .font(.subheadline)
          .foregroundColor(.secondary)
        Text(store.workspace.remotePath)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      HStack(spacing: 8) {
        serverBadge
        statusPill
      }
    }
    .padding()
    .background(.quaternary)
  }

  private var statusPill: some View {
    let state = store.onlineState
    let (color, text): (Color, String) = {
      switch state {
      case .idle: return (.gray, "Idle")
      case let .spawning(phase): return (.orange, phase.rawValue)
      case let .online(port): return (.green, "Online :\(port)")
      case .error: return (.red, "Error")
      }
    }()

    return HStack(spacing: 6) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(text).font(.caption)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(color.opacity(0.15))
    .cornerRadius(12)
  }

  private var serverBadge: some View {
    let state = store.serverConnection
    let color: Color = {
      switch state {
      case .connected: return .green
      case .connecting: return .orange
      case .error: return .red
      case .disconnected: return .gray
      }
    }()

    let text: String = {
      switch state {
      case .connected: return "SSH"
      case .connecting: return "SSH"
      case .error: return "SSH"
      case .disconnected: return "SSH"
      }
    }()

    return HStack(spacing: 6) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(text).font(.caption)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(color.opacity(0.15))
    .cornerRadius(12)
  }

  private var activityView: some View {
    VStack(spacing: 12) {
      Image(systemName: "chart.line.uptrend.xyaxis")
        .font(.largeTitle)
        .foregroundColor(.secondary)
      Text("Activity")
        .font(.title2)
        .fontWeight(.medium)
      Text("Workspace activity will appear here")
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var terminalView: some View {
    VStack(spacing: 12) {
      Image(systemName: "terminal")
        .font(.largeTitle)
        .foregroundColor(.secondary)
      Text("Terminal")
        .font(.title2)
        .fontWeight(.medium)
      Text("Interactive terminal coming soon")
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var filesView: some View {
    VStack(spacing: 12) {
      Image(systemName: "folder")
        .font(.largeTitle)
        .foregroundColor(.secondary)
      Text("Files")
        .font(.title2)
        .fontWeight(.medium)
      Text("File browser coming soon")
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        onlineState: .online(port: 8080)
      ),
      reducer: { WorkspaceInteractionFeature() }
    )
  )
}
