import ComposableArchitecture
import OpenCoderCore
import SwiftUI

struct HomeView: View {
  @Environment(\.scenePhase) private var scenePhase
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
      ServersView(
        store: store.scope(state: \.servers, action: \.servers)
      ) { task in
          liveActivityStore?.send(.startActivity(task))
        }
      .tabItem {
        Label("Servers", systemImage: "server.rack")
      }
      .tag(HomeFeature.Tab.servers)

      WorkspacesView(
        store: store.scope(state: \.workspaces, action: \.workspaces)
      )
      .tabItem {
        Label("Workspaces", systemImage: "folder.badge.gear")
      }
      .tag(HomeFeature.Tab.workspaces)

      SettingsView(store: store.scope(state: \.settings, action: \.settings))
        .tabItem {
          Label("Settings", systemImage: "gear")
        }
        .tag(HomeFeature.Tab.settings)
    }
    .onChange(of: scenePhase) { _, newPhase in
      switch newPhase {
      case .active:
        store.send(.servers(.appWillEnterForeground))
      case .background:
        store.send(.servers(.appDidEnterBackground))
      default:
        break
      }
    }
  }
}

#Preview {
  HomeView(
    store: .init(
      initialState: .init()
    ) {
        HomeFeature()
      }
  )
}
