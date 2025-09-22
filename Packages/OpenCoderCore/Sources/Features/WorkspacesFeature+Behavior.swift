import ComposableArchitecture
import Protocols
import Foundation
import Models

private typealias Send = WorkspacesFeature.Action

extension WorkspacesFeature {
  func handleWorkspacesLoaded(state: inout State, workspaces: [WorkspaceState]) -> Effect<Action> {
    // Preserve online state and metadata when reloading from storage
    let existingByID: [UUID: WorkspaceState] = Dictionary(
      uniqueKeysWithValues: state.workspaces.map { ($0.workspace.id, $0) }
    )

    state.workspaces = workspaces.map { loaded in
      var merged = loaded
      if let existing = existingByID[loaded.workspace.id] {
        merged.onlineState = existing.onlineState
        merged.lastConnectedAt = existing.lastConnectedAt
        merged.openCodeSession = existing.openCodeSession
        merged.openCodeSessions = existing.openCodeSessions
        merged.forwardedPort = existing.forwardedPort
        merged.remotePort = existing.remotePort
        merged.sessions = existing.sessions
        merged.isRefreshing = existing.isRefreshing
      }
      return merged
    }
    state.isLoading = false

    guard let selectedID = state.selectedWorkspace,
      let selectedWorkspace = state.workspaces.first(where: { $0.id == selectedID }),
      state.workspaceInteraction != nil
    else {
      return .none
    }

    state.workspaceInteraction?.workspace = selectedWorkspace.workspace
    state.workspaceInteraction?.onlineState = selectedWorkspace.onlineState
    state.workspaceInteraction?.forwardedPort = selectedWorkspace.forwardedPort
    state.workspaceInteraction?.chat.serverURL = selectedWorkspace.forwardedPort.map { port in
      URL(string: "http://127.0.0.1:\(port)")
    } ?? nil

    return .merge(
      .send(.workspaceInteraction(.forwardedPortUpdated(selectedWorkspace.forwardedPort))),
      .send(.workspaceInteraction(.openCodeSessionUpdated(selectedWorkspace.openCodeSession)))
    )
  }

  func handleAddWorkspace(state: inout State) -> Effect<Action> {
    state.isAddingWorkspace = true
    return .none
  }

  func handleAddWorkspaceCompleted(state: inout State, workspace: Workspace) -> Effect<Action> {
    let workspaceState = WorkspaceState(workspace: workspace)
    state.workspaces.append(workspaceState)
    state.isAddingWorkspace = false
    WorkspacesStorage.saveWorkspacesToStorage(state.workspaces.map { $0.workspace })
    return .none
  }

  func handleRemoveWorkspace(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
    let cleanup = stopPortForward(&state, id: id)
    state.workspaces.removeAll { $0.id == id }
    WorkspacesStorage.saveWorkspacesToStorage(state.workspaces.map { $0.workspace })

    if state.selectedWorkspace == id {
      state.showingWorkspaceInteraction = false
      state.selectedWorkspace = nil
      state.workspaceInteraction = nil
    }

    return cleanup
  }

  func handleDismissAddWorkspace(state: inout State) -> Effect<Action> {
    state.isAddingWorkspace = false
    return .none
  }

  func handleShowLiveOutput(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
    state.selectedWorkspace = id
    state.interactionInitialTab = .liveOutput
    state.showingWorkspaceInteraction = true
    if let workspace = state.workspaces.first(where: { $0.id == id }) {
      state.workspaceInteraction = WorkspaceInteractionFeature.State(
        workspace: workspace.workspace,
        onlineState: workspace.onlineState,
        selectedTab: .liveOutput,
        sessionID: workspace.openCodeSession?.id,
        forwardedPort: workspace.forwardedPort
      )
    }
    return .none
  }

  func handleTask(state: inout State) -> Effect<Action> {
    state.isLoading = true
    return .run { send in
      let workspaces = WorkspacesStorage.loadWorkspacesFromStorage()
      let workspaceStates = workspaces.map { WorkspaceState(workspace: $0) }
      await send(.workspacesLoaded(workspaceStates))
    }
  }

    private func resetWorkspaceState(_ state: inout State, index: Int, id: WorkspaceState.ID) {
      state.workspaces[index].onlineState = .spawning(phase: .sshConnection)
      state.workspaces[index].openCodeSession = nil
      state.workspaces[index].openCodeSessions = []
      state.workspaces[index].forwardedPort = nil
      state.workspaces[index].remotePort = nil
      state.selectedWorkspace = id
      state.interactionInitialTab = .activity
      state.showingWorkspaceInteraction = true
    }

   private func createSSHConfigErrorEffect(
     cleanup: Effect<Action>,
     workspaceID: WorkspaceState.ID
   ) -> Effect<Action> {
     .merge(
       cleanup,
       .run { send in
         let errorMessage =
           "No SSH server configuration found for this workspace. "
           + "Please associate this workspace with a server."
         await send(.workspaceOpened(workspaceID, .failure(.connectionFailed(errorMessage))))
       }
     )
   }

   func handleOpenWorkspace(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
     guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }

     resetWorkspaceState(&state, index: index, id: id)
     let workspace = state.workspaces[index].workspace

      state.workspaceInteraction = WorkspaceInteractionFeature.State(
        workspace: workspace,
        onlineState: .idle, // Start with idle, then transition to spawning
        selectedTab: state.interactionInitialTab,
        sessionID: nil
      )

     let cleanup = stopPortForward(&state, id: id)

     guard let serverConfig = WorkspacesStorage.loadSSHConfigForWorkspace(workspace) else {
       return createSSHConfigErrorEffect(cleanup: cleanup, workspaceID: id)
     }

      return .merge(
        cleanup,
        .send(.workspaceInteraction(.onlineStateChanged(.spawning(phase: .sshConnection)))),
        spawnWorkspaceSession(
          workspace: workspace,
          workspaceID: id,
          serverConfig: serverConfig
        )
      )
   }

   private func updateWorkspaceStateWithSpawnResult(
     _ state: inout State,
     index: Int,
     result: Result<WorkspaceService.SpawnResult, SSHError>,
     isSelected: Bool
   ) -> Bool {
     var workspaceState = state.workspaces[index]

     switch result {
     case .success(let spawnResult):
       if spawnResult.online {
         workspaceState.onlineState = .online(port: spawnResult.port)
         workspaceState.lastConnectedAt = Date()
         workspaceState.isRefreshing = false
       } else {
         workspaceState.onlineState = .error(
           spawnResult.error?.localizedDescription ?? "Unknown error"
         )
         workspaceState.isRefreshing = false
       }
     case .failure(let error):
       workspaceState.onlineState = .error(error.localizedDescription)
       workspaceState.isRefreshing = false
     }

     state.workspaces[index] = workspaceState

     if isSelected {
       state.workspaceInteraction?.onlineState = workspaceState.onlineState
       state.workspaceInteraction?.workspace = workspaceState.workspace
     }

     switch workspaceState.onlineState {
     case .online: return true
     case .idle, .spawning, .error: return false
     }
   }

   func handleWorkspaceOpened(
     state: inout State,
     id: WorkspaceState.ID,
     result: Result<WorkspaceService.SpawnResult, SSHError>
   ) -> Effect<Action> {
     guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }

     let isSelected = state.selectedWorkspace == id
     let isOnline = updateWorkspaceStateWithSpawnResult(
       &state,
       index: index,
       result: result,
       isSelected: isSelected
     )

     if isOnline {
       return .none
     } else {
       return stopPortForward(&state, id: id)
     }
   }

  func handleHideWorkspaceInteraction(state: inout State) -> Effect<Action> {
    state.showingWorkspaceInteraction = false
    state.selectedWorkspace = nil
    state.interactionInitialTab = .activity
    state.workspaceInteraction = nil
    return .none
  }

  func handleRefreshWorkspace(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
    guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }
    guard case .online = state.workspaces[index].onlineState else { return .none }

    guard let forwardedPort = state.workspaces[index].forwardedPort else {
      state.workspaces[index].isRefreshing = false
      return .none
    }

    state.workspaces[index].isRefreshing = true
    let workspace = state.workspaces[index].workspace
    let existingSessions = state.workspaces[index].sessions
    let existingOpenCodeSessions = state.workspaces[index].openCodeSessions

    return fetchSessionsEffect(
      workspace: workspace,
      workspaceID: id,
      forwardedPort: forwardedPort,
      fallbackSessions: existingSessions,
      fallbackOpenCodeSessions: existingOpenCodeSessions
    )
  }

   func handleWorkspaceRefreshed(
     state: inout State,
     id: WorkspaceState.ID,
     sessions: [SessionMeta],
     openCodeSessions: [OpenCodeSession]
   ) -> Effect<Action> {
     guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }

     state.workspaces[index].sessions = sessions
     state.workspaces[index].openCodeSessions = openCodeSessions
     state.workspaces[index].openCodeSession = openCodeSessions.first
     state.workspaces[index].isRefreshing = false
     let interactionWorkspace = state.workspaces[index].workspace

     guard state.selectedWorkspace == id else { return .none }

     state.workspaceInteraction?.workspace = interactionWorkspace

     return .send(
       .workspaceInteraction(.openCodeSessionUpdated(openCodeSessions.first))
     )
   }

   func handleCleanAndRetry(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
     guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }

     resetWorkspaceState(&state, index: index, id: id)
     let workspace = state.workspaces[index].workspace

     let cleanup = stopPortForward(&state, id: id)

     guard let serverConfig = WorkspacesStorage.loadSSHConfigForWorkspace(workspace) else {
       return createSSHConfigErrorEffect(cleanup: cleanup, workspaceID: id)
     }

     if state.selectedWorkspace == id {
       state.workspaceInteraction?.workspace = workspace
     }

     let spawnEffect = spawnWorkspaceSession(
       workspace: workspace,
       workspaceID: id,
       serverConfig: serverConfig
     )

     if state.selectedWorkspace == id {
       return .merge(
         cleanup,
         .send(.workspaceInteraction(.openCodeSessionUpdated(nil))),
         spawnEffect
       )
     }

     return .merge(cleanup, spawnEffect)
   }

  func handleSpawnPhaseUpdated(
    state: inout State,
    id: WorkspaceState.ID,
    phase: SpawnPhase
  ) -> Effect<Action> {
    guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }

    var workspaceState = state.workspaces[index]
    workspaceState.onlineState = .spawning(phase: phase)
    state.workspaces[index] = workspaceState

    if state.selectedWorkspace == id {
      state.workspaceInteraction?.onlineState = workspaceState.onlineState
    }

    return .none
  }

   func spawnWorkspaceSession(
     workspace: Workspace,
     workspaceID: WorkspaceState.ID,
     serverConfig: SSHServerConfiguration
   ) -> Effect<Action> {
     return .run { send in
       do {
         await send(.spawnPhaseUpdated(workspaceID, .sshConnection))
         let workspaceService = WorkspaceService(config: serverConfig)
         await send(.spawnPhaseUpdated(workspaceID, .openCodeSpawn))
         let spawnResult = try await workspaceService.attachOrSpawn(workspace: workspace)

         guard spawnResult.online else {
           await send(.workspaceOpened(workspaceID, .success(spawnResult)))
           return
         }

         await send(.spawnPhaseUpdated(workspaceID, .portForwarding))
         let token = try await portForwarding.startForward(
           workspace: workspace,
           serverConfig: serverConfig,
           remotePort: spawnResult.port
         )

         await send(.workspacePortForwardEstablished(workspaceID, token))
         await send(.spawnPhaseUpdated(workspaceID, .apiHandshake))

         let serverURL = URL(string: "http://127.0.0.1:\(token.localPort)")!
         let apiConfiguration = OpenCodeConfiguration(
           serverURL: serverURL,
           timeout: openCodeConfiguration.timeout,
           retryCount: openCodeConfiguration.retryCount
         )
         let apiClient = openCodeAPIFactory.make(apiConfiguration)

         do {
           _ = try await apiClient.getConfig()
         } catch {
           let connectionError = SSHError.connectionFailed(
             "Failed to connect to OpenCode server API: \(error.localizedDescription)"
           )
           await send(.workspaceOpened(workspaceID, .failure(connectionError)))
           return
         }

         let forwardedResult = WorkspaceService.SpawnResult(
           port: token.localPort,
           online: true,
           error: spawnResult.error
         )
         await send(.workspaceOpened(workspaceID, .success(forwardedResult)))
         await send(.refreshWorkspace(workspaceID))
       } catch {
         if let sshError = error as? SSHError {
           await send(.workspaceOpened(workspaceID, .failure(sshError)))
         } else {
           let connectionError = SSHError.connectionFailed(error.localizedDescription)
           await send(.workspaceOpened(workspaceID, .failure(connectionError)))
         }
       }
     }
   }

}
