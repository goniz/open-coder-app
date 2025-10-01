import ComposableArchitecture
import OpenCoderCore
import SwiftUI

public struct AppView: View {
  let store: StoreOf<AppFeature>

  public init(store: StoreOf<AppFeature>) {
    self.store = store
  }

  public var body: some View {
    Group {
      if store.showOnboarding {
        OnboardingView(store: store.scope(state: \.onboarding, action: \.onboarding))
      } else {
        HomeView(
          store: store.scope(state: \.home, action: \.home),
          liveActivityStore: store.scope(state: \.liveActivity, action: \.liveActivity)
        )
      }
    }
    .task {
      await store.send(.task).finish()
    }
    .alert("Error", isPresented: Binding(
      get: { store.globalError != nil },
      set: { if !$0 { store.send(.dismissGlobalError) } }
    )) {
      Button("OK") {
        store.send(.dismissGlobalError)
      }
    } message: {
      if let error = store.globalError {
        Text(error)
      }
    }
  }
}

#Preview {
  AppView(
    store: .init(
      initialState: .init()
    ) {
        AppFeature()
      }
  )
}
