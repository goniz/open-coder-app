import ComposableArchitecture
import DependencyClients
import Foundation
import Models

@Reducer
package struct WorkspacesFeature {
    @ObservableState
    package struct State: Equatable {
        package var workspaces: [WorkspaceState] = []
        package var isLoading = false
        package var isAddingWorkspace = false
        package var selectedWorkspace: WorkspaceState.ID?
        package var showingLiveOutput = false
        
        package init() {}
    }
    
    package struct WorkspaceState: Equatable, Identifiable {
        package let id = UUID()
        package var workspace: Workspace
        package var onlineState: WorkspaceOnlineState = .idle
        package var lastConnectedAt: Date?
        package var sessions: [SessionMeta] = []
        package var isRefreshing = false
        
        package init(workspace: Workspace) {
            self.workspace = workspace
        }
    }
    
    package enum Action: Equatable {
        case task
        case workspacesLoaded([WorkspaceState])
        case addWorkspace
        case addWorkspaceCompleted(Workspace)
        case openWorkspace(WorkspaceState.ID)
        case workspaceOpened(WorkspaceState.ID, Result<WorkspaceService.SpawnResult, SSHError>)
        case refreshWorkspace(WorkspaceState.ID)
        case workspaceRefreshed(WorkspaceState.ID, [SessionMeta])
        case removeWorkspace(WorkspaceState.ID)
        case dismissAddWorkspace
        case showLiveOutput(WorkspaceState.ID)
        case hideLiveOutput
        case cleanAndRetry(WorkspaceState.ID)
        case spawnPhaseUpdated(WorkspaceState.ID, SpawnPhase)
    }
    
    package init() {}
    
    package var body: some ReducerOf<Self> {
        Reduce(core)
    }
    
    package func core(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .task:
            return handleTask(state: &state)
            
        case let .workspacesLoaded(workspaces):
            state.workspaces = workspaces
            state.isLoading = false
            return .none
            
        case .addWorkspace:
            state.isAddingWorkspace = true
            return .none
            
        case let .addWorkspaceCompleted(workspace):
            let workspaceState = WorkspaceState(workspace: workspace)
            state.workspaces.append(workspaceState)
            state.isAddingWorkspace = false
            saveWorkspacesToStorage(state.workspaces)
            return .none
            
        case let .openWorkspace(id):
            return handleOpenWorkspace(state: &state, id: id)
            
        case let .workspaceOpened(id, result):
            return handleWorkspaceOpened(state: &state, id: id, result: result)
            
        case let .refreshWorkspace(id):
            return handleRefreshWorkspace(state: &state, id: id)
            
        case let .workspaceRefreshed(id, sessions):
            return handleWorkspaceRefreshed(state: &state, id: id, sessions: sessions)
            
        case let .removeWorkspace(id):
            state.workspaces.removeAll { $0.id == id }
            saveWorkspacesToStorage(state.workspaces)
            return .none
            
        case .dismissAddWorkspace:
            state.isAddingWorkspace = false
            return .none
            
        case let .showLiveOutput(id):
            state.selectedWorkspace = id
            state.showingLiveOutput = true
            return .none
            
        case .hideLiveOutput:
            state.showingLiveOutput = false
            state.selectedWorkspace = nil
            return .none
            
        case let .cleanAndRetry(id):
            return handleCleanAndRetry(state: &state, id: id)
            
        case let .spawnPhaseUpdated(id, phase):
            return handleSpawnPhaseUpdated(state: &state, id: id, phase: phase)
        }
    }
    
    private func handleTask(state: inout State) -> Effect<Action> {
        state.isLoading = true
        return .run { send in
            let workspaces = loadWorkspacesFromStorage()
            let workspaceStates = workspaces.map { WorkspaceState(workspace: $0) }
            await send(.workspacesLoaded(workspaceStates))
        }
    }
    
    private func handleOpenWorkspace(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }
        
        state.workspaces[index].onlineState = .spawning(phase: .ssh)
        let workspace = state.workspaces[index].workspace
        
        return .run { send in
            do {
                let sshClient = SSHClient()
                let workspaceService = WorkspaceService(sshClient: sshClient)
                let result = try await workspaceService.attachOrSpawn(workspace: workspace)
                await send(.workspaceOpened(id, .success(result)))
            } catch {
                if let sshError = error as? SSHError {
                    await send(.workspaceOpened(id, .failure(sshError)))
                } else {
                    await send(.workspaceOpened(id, .failure(.connectionFailed(error.localizedDescription))))
                }
            }
        }
    }
    
    private func handleWorkspaceOpened(state: inout State, id: WorkspaceState.ID, result: Result<WorkspaceService.SpawnResult, SSHError>) -> Effect<Action> {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }
        
        switch result {
        case .success(let spawnResult):
            if spawnResult.online {
                state.workspaces[index].onlineState = .online(port: spawnResult.port)
                state.workspaces[index].lastConnectedAt = Date()
                // Fetch sessions after successful connection
                return .run { send in
                    await send(.refreshWorkspace(id))
                }
            } else {
                state.workspaces[index].onlineState = .error(spawnResult.error?.localizedDescription ?? "Unknown error")
            }
        case .failure(let error):
            state.workspaces[index].onlineState = .error(error.localizedDescription)
        }
        
        return .none
    }
    
    private func handleRefreshWorkspace(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }
        guard case .online(_) = state.workspaces[index].onlineState else { return .none }
        
        state.workspaces[index].isRefreshing = true
        let workspaceId = state.workspaces[index].workspace.id
        
        return .run { send in
            // Mock session fetch - in real implementation would fetch from server
            try await Task.sleep(for: .seconds(1))
            let mockSessions = [
                SessionMeta(
                    id: "1",
                    title: "Code Review",
                    lastMessagePreview: "Added new feature for workspace management",
                    updatedAt: Date(),
                    workspaceId: workspaceId
                ),
                SessionMeta(
                    id: "2",
                    title: "Bug Fix",
                    lastMessagePreview: "Fixed SSH connection issue",
                    updatedAt: Date().addingTimeInterval(-300),
                    workspaceId: workspaceId
                )
            ]
            await send(.workspaceRefreshed(id, mockSessions))
        }
    }
    
    private func handleWorkspaceRefreshed(state: inout State, id: WorkspaceState.ID, sessions: [SessionMeta]) -> Effect<Action> {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }
        
        state.workspaces[index].sessions = sessions
        state.workspaces[index].isRefreshing = false
        
        return .none
    }
    
    private func handleCleanAndRetry(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }
        
        state.workspaces[index].onlineState = .spawning(phase: .ssh)
        let workspace = state.workspaces[index].workspace
        
        return .run { send in
            do {
                let sshClient = SSHClient()
                let workspaceService = WorkspaceService(sshClient: sshClient)
                let result = try await workspaceService.cleanAndRetry(workspace: workspace)
                await send(.workspaceOpened(id, .success(result)))
            } catch {
                if let sshError = error as? SSHError {
                    await send(.workspaceOpened(id, .failure(sshError)))
                } else {
                    await send(.workspaceOpened(id, .failure(.connectionFailed(error.localizedDescription))))
                }
            }
        }
    }
    
    private func handleSpawnPhaseUpdated(state: inout State, id: WorkspaceState.ID, phase: SpawnPhase) -> Effect<Action> {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }
        
        state.workspaces[index].onlineState = .spawning(phase: phase)
        
        return .none
    }
    
    private func loadWorkspacesFromStorage() -> [Workspace] {
        guard let data = UserDefaults.standard.data(forKey: "savedWorkspaces") else { return [] }
        do {
            let workspaces = try JSONDecoder().decode([Workspace].self, from: data)
            return workspaces
        } catch {
            print("Failed to load workspaces: \(error)")
            return []
        }
    }
    
    private func saveWorkspacesToStorage(_ workspaceStates: [WorkspaceState]) {
        let workspaces = workspaceStates.map { $0.workspace }
        do {
            let data = try JSONEncoder().encode(workspaces)
            UserDefaults.standard.set(data, forKey: "savedWorkspaces")
        } catch {
            print("Failed to save workspaces: \(error)")
        }
    }
}