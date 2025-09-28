import ComposableArchitecture
import Protocols
import Foundation
import Models

extension WorkspacesFeature {
  func fetchSessionsEffect(
    workspace: Workspace,
    workspaceID: WorkspaceState.ID,
    forwardedPort: Int,
    fallbackSessions: [SessionMeta]
  ) -> Effect<Action> {
    let baseConfiguration = openCodeConfiguration

    guard let serverURL = URL(string: "http://127.0.0.1:\(forwardedPort)") else {
      return .run { send in
        await send(.workspaceRefreshed(workspaceID, fallbackSessions, []))
      }
    }

    let configuration = OpenCodeConfiguration(
      serverURL: serverURL,
      timeout: baseConfiguration.timeout,
      retryCount: baseConfiguration.retryCount
    )
    let apiClient = openCodeAPIFactory.make(configuration)

    return .run { send in
      do {
        let (metadata, openCodeSessions) = try await loadSessionMetadata(
          workspace: workspace,
          apiClient: apiClient
        )
        await send(.workspaceRefreshed(workspaceID, metadata, openCodeSessions))
      } catch {
        await send(.workspaceRefreshed(workspaceID, fallbackSessions, []))
      }
    }
  }

  func loadSessionMetadata(
    workspace: Workspace,
    apiClient: OpenCodeAPIClientProtocol
  ) async throws -> ([SessionMeta], [OpenCodeSession]) {
    let sessions = try await apiClient.listSessions()

    var metadata: [SessionMeta] = []
    metadata.reserveCapacity(sessions.count)

    for session in sessions {
      let messages = try? await apiClient.getMessages(sessionID: session.id)
      let preview = previewText(for: messages ?? [])
      let updatedAt = messages?.last?.timestamp ?? session.updatedAt

      metadata.append(
        SessionMeta(
          id: session.id,
          title: makeSessionTitle(for: session, workspace: workspace),
          lastMessagePreview: preview,
          updatedAt: updatedAt,
          workspaceId: workspace.id
        )
      )
    }

    let sortedMetadata = metadata.sorted(by: { $0.updatedAt > $1.updatedAt })
    return (sortedMetadata, sessions)
  }

  func previewText(for messages: [OpenCodeMessage]) -> String {
    guard let lastMessage = messages.last else { return "" }
    for part in lastMessage.parts {
      if case let .text(content) = part {
        return content
      }
    }
    return ""
  }

  func makeSessionTitle(
    for session: OpenCodeSession,
    workspace: Workspace
  ) -> String {
    if session.id.hasPrefix(workspace.name) {
      return session.id
    }
    return "\(workspace.name) – \(session.id.prefix(6))"
  }
}
