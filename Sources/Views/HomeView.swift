import ComposableArchitecture
import Features
import SwiftUI

struct HomeView: View {
  @Bindable var store: StoreOf<HomeFeature>
  var liveActivityStore: StoreOf<LiveActivityFeature>?

  init(store: StoreOf<HomeFeature>, liveActivityStore: StoreOf<LiveActivityFeature>? = nil) {
    self.store = store
    self.liveActivityStore = liveActivityStore
  }

  var body: some View {
    TabView(
      selection: Binding(
        get: { store.selectedTab },
        set: { store.send(.tabSelected($0)) }
      )
    ) {
      WorkspacesView(
        store: store.scope(state: \.workspaces, action: \.workspaces)
      )
      .tabItem {
        Label("Workspaces", systemImage: "folder.badge.gear")
      }
      .tag(HomeFeature.Tab.workspaces)

      ServersView(
        store: store.scope(state: \.servers, action: \.servers),
        onStartTask: { task in
          liveActivityStore?.send(.startActivity(task))
        }
      )
      .tabItem {
        Label("Servers", systemImage: "server.rack")
      }
      .tag(HomeFeature.Tab.servers)

      ProjectsView(store: store.scope(state: \.projects, action: \.projects))
        .tabItem {
          Label("Projects", systemImage: "folder")
        }
        .tag(HomeFeature.Tab.projects)

      ChatView(store: store.scope(state: \.chat, action: \.chat))
        .tabItem {
          Label("Chat", systemImage: "message")
        }
        .tag(HomeFeature.Tab.chat)

      SettingsView(store: store.scope(state: \.settings, action: \.settings))
        .tabItem {
          Label("Settings", systemImage: "gear")
        }
        .tag(HomeFeature.Tab.settings)
    }
  }
}

#Preview {
  HomeView(
    store: .init(
      initialState: .init(),
      reducer: {
        HomeFeature()
      }
    )
  )
}
