import ComposableArchitecture
import Features
import Models
import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

struct WorkspaceDashboardView: View {
  @Bindable var store: StoreOf<WorkspaceDashboardFeature>

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        HeaderView(workspace: store.workspace, onlineState: store.onlineState)

        Picker("Tab", selection: $store.selectedTab.sending(\.tabSelected)) {
          ForEach(WorkspaceDashboardFeature.Tab.allCases, id: \.self) { tab in
            Text(tab.rawValue).tag(tab)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)

        tabContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .navigationTitle(store.workspace.name)
    }
  }

  @ViewBuilder
  private var tabContent: some View {
    switch store.selectedTab {
    case .sessions:
      SessionsListView(
        sessions: store.sessions,
        isRefreshing: store.isRefreshing,
        onRefresh: { store.send(.refreshSessions) }
      )
    case .liveOutput:
      WorkspaceLiveOutputTabView(workspace: store.workspace)
    case .repo:
      VStack {
        Image(systemName: "folder")
          .font(.largeTitle)
          .foregroundColor(.secondary)
        Text("Repository")
          .font(.title2)
          .fontWeight(.medium)
        Text("Coming Soon")
          .foregroundColor(.secondary)
      }
    case .terminals:
      VStack {
        Image(systemName: "terminal")
          .font(.largeTitle)
          .foregroundColor(.secondary)
        Text("Terminals")
          .font(.title2)
          .fontWeight(.medium)
        Text("Coming Soon")
          .foregroundColor(.secondary)
      }
    case .activity:
      VStack {
        Image(systemName: "chart.line.uptrend.xyaxis")
          .font(.largeTitle)
          .foregroundColor(.secondary)
        Text("Activity")
          .font(.title2)
          .fontWeight(.medium)
        Text("Coming Soon")
          .foregroundColor(.secondary)
      }
    }
  }
}

private struct HeaderView: View {
  let workspace: Workspace
  let onlineState: WorkspaceOnlineState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(workspace.host)
            .font(.headline)

          Text("\(workspace.user)@\(workspace.host):\(workspace.remotePath)")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        StatusPill(state: onlineState)
      }
    }
    .padding()
    .background(.quaternary)
  }
}

private struct StatusPill: View {
  let state: WorkspaceOnlineState

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)

      Text(text)
        .font(.caption)
        .fontWeight(.medium)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(color.opacity(0.15))
    .cornerRadius(12)
  }

  private var color: Color {
    switch state {
    case .idle:
      return .gray
    case .spawning:
      return .orange
    case .online:
      return .green
    case .error:
      return .red
    }
  }

  private var text: String {
    switch state {
    case .idle:
      return "Idle"
    case .spawning(let phase):
      return phase.rawValue.capitalized
    case .online(let port):
      return "Online :\(port)"
    case .error:
      return "Error"
    }
  }
}

private struct SessionsListView: View {
  let sessions: [SessionMeta]
  let isRefreshing: Bool
  let onRefresh: () -> Void

  var body: some View {
    List {
      ForEach(sessions, id: \.id) { session in
        SessionRow(session: session)
      }
    }
    .refreshable {
      onRefresh()
    }
    .overlay {
      if sessions.isEmpty {
        VStack {
          Image(systemName: "message")
            .font(.largeTitle)
            .foregroundColor(.secondary)
          Text("No Sessions")
            .font(.title2)
            .fontWeight(.medium)
          Text("Pull down to refresh")
            .foregroundColor(.secondary)
        }
      }
    }
  }
}

private struct SessionRow: View {
  let session: SessionMeta

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(session.title)
        .font(.headline)

      Text(session.lastMessagePreview)
        .font(.body)
        .foregroundColor(.secondary)
        .lineLimit(2)

      Text(session.updatedAt, style: .relative)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  WorkspaceDashboardView(
    store: .init(
      initialState: .init(
        workspace: Workspace(
          name: "Test Workspace",
          host: "example.com",
          user: "developer",
          remotePath: "/home/developer/project"
        ),
        onlineState: .online(port: 8080)
      ),
      reducer: {
        WorkspaceDashboardFeature()
      }
    )
  )
}
