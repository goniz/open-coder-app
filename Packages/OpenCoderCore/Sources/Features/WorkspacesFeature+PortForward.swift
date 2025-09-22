import ComposableArchitecture
import Protocols
import Foundation
import Models

extension WorkspacesFeature {
  func handlePortForwardEstablished(
    state: inout State,
    id: WorkspaceState.ID,
    token: PortForwardToken
  ) -> Effect<Action> {
    var effects: [Effect<Action>] = []
    state.portForwardTokens[id] = token
    if let index = state.workspaces.firstIndex(where: { $0.id == id }) {
      state.workspaces[index].forwardedPort = token.localPort
      state.workspaces[index].remotePort = token.remotePort
      let interactionWorkspace = state.workspaces[index].workspace

      if state.selectedWorkspace == id {
        state.workspaceInteraction?.workspace = interactionWorkspace
        effects.append(
          .send(.workspaceInteraction(.forwardedPortUpdated(token.localPort)))
        )
        effects.append(.send(.workspaceInteraction(.chat(.task))))
      }
    }

    return .merge(effects)
  }

  func stopPortForward(_ state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
    guard let token = state.portForwardTokens.removeValue(forKey: id) else { return .none }

    var effects: [Effect<Action>] = []

    if let index = state.workspaces.firstIndex(where: { $0.id == id }) {
      state.workspaces[index].forwardedPort = nil
      state.workspaces[index].remotePort = nil
    }

    if state.selectedWorkspace == id {
      state.workspaceInteraction?.forwardedPort = nil
      state.workspaceInteraction?.chat.serverURL = nil
      effects.append(.send(.workspaceInteraction(.forwardedPortUpdated(nil))))
    }

    effects.append(.run { _ in
      await portForwarding.stopForward(token)
    })

    return .merge(effects)
  }
}
