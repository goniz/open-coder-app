import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import HTTPTypes
import Protocols
import Dependencies
import Models

public struct LiveOpenCodeAPIClient: OpenCodeAPIClientProtocol {
  let client: Client
  public let configuration: OpenCodeConfiguration

  public init(
    configuration: OpenCodeConfiguration,
    transport: any ClientTransport = AsyncHTTPClientTransport()
  ) {
    self.configuration = configuration
    self.client = Client(
      serverURL: configuration.serverURL,
      transport: transport
    )
  }

}

// MARK: - Session Management

extension LiveOpenCodeAPIClient {
  public func listSessions() async throws -> [OpenCodeSession] {
    log("OpenCode API: Listing sessions from \(configuration.serverURL)")

    let input = Operations.session_period_list.Input()

    do {
      let response = try await client.session_period_list(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case let .json(sessionList):
          let sessions = sessionList.map { sessionData in
            // Convert API response to domain model using actual properties
            return OpenCodeSession(
              id: sessionData.id,
              createdAt: Date(timeIntervalSince1970: sessionData.time.created),
              updatedAt: Date(timeIntervalSince1970: sessionData.time.updated),
              isActive: true, // Assume active if listed
              title: sessionData.title
            )
          }
          log("OpenCode API: Successfully retrieved \(sessions.count) sessions")
          return sessions
        }
      case let .undocumented(statusCode, _):
        log("OpenCode API: List sessions failed with undocumented status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Unexpected status code: \(statusCode)")
      }
    } catch {
      log("OpenCode API: List sessions failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  public func createSession() async throws -> OpenCodeSession {
    log("OpenCode API: Creating new session")

    let input = Operations.session_period_create.Input()

    do {
      let response = try await client.session_period_create(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case let .json(sessionData):
          let session = OpenCodeSession(
            id: sessionData.id,
            createdAt: Date(timeIntervalSince1970: sessionData.time.created),
            updatedAt: Date(timeIntervalSince1970: sessionData.time.updated),
            isActive: true,
            title: sessionData.title
          )
          log("OpenCode API: Successfully created session with ID: \(session.id)")
          return session
        }
      case .badRequest:
        log("OpenCode API: Create session failed - bad request", level: .error)
        throw OpenCodeAPIError.badRequest("Failed to create session")
      case let .undocumented(statusCode, _):
        log("OpenCode API: Create session failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to create session: \(statusCode)")
      }
    } catch {
      log("OpenCode API: Create session failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  public func deleteSession(id: String) async throws {
    log("OpenCode API: Deleting session: \(id)")

    let input = Operations.session_period_delete.Input(path: .init(id: id))

    do {
      let response = try await client.session_period_delete(input)

      switch response {
      case .ok:
        log("OpenCode API: Successfully deleted session: \(id)")
        return
      case let .undocumented(statusCode, _):
        log("OpenCode API: Delete session failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to delete session: \(statusCode)")
      }
    } catch {
      log("OpenCode API: Delete session failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  public func getSession(id: String) async throws -> OpenCodeSession {
    let input = Operations.session_period_get.Input(path: .init(id: id))
    let response = try await client.session_period_get(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(sessionData):
        return OpenCodeSession(
          id: sessionData.id,
          createdAt: Date(timeIntervalSince1970: sessionData.time.created),
          updatedAt: Date(timeIntervalSince1970: sessionData.time.updated),
          isActive: true,
          title: sessionData.title
        )
      }
    case .undocumented:
      throw OpenCodeAPIError.sessionNotFound(id)
    }
  }

}

// MARK: - Event Streaming

extension LiveOpenCodeAPIClient {
  public func subscribeToEvents() async throws -> AsyncThrowingStream<OpenCodeEvent, Error> {
    log("OpenCode API: Subscribing to events stream")

    let input = Operations.event_period_subscribe.Input()

    do {
      let response = try await client.event_period_subscribe(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case let .text_event_hyphen_stream(httpBody):
          return createEventStream(from: httpBody)
        }
      case let .undocumented(statusCode, _):
        log(
          "OpenCode API: Subscribe to events failed with status code: \(statusCode)",
          level: .error
        )
        throw OpenCodeAPIError.serverError("Failed to subscribe to events: \(statusCode)")
      }
    } catch {
      log("OpenCode API: Subscribe to events failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  private func createEventStream(
    from httpBody: HTTPBody
  ) -> AsyncThrowingStream<OpenCodeEvent, Error> {
    return AsyncThrowingStream { continuation in
      Task {
        do {
          for try await chunk in httpBody {
            guard let chunkString = String(bytes: chunk, encoding: .utf8) else {
              continue
            }

            for line in chunkString.split(separator: "\n") {
              let lineStr = String(line)

              if lineStr.hasPrefix("data: ") {
                let jsonString = String(lineStr.dropFirst(6))

                if let event = parseEvent(from: jsonString) {
                  continuation.yield(event)
                }
              }
            }
          }
          log("OpenCode API: Event stream ended")
          continuation.finish()
        } catch {
          log(
            "OpenCode API: Event stream error: \(error.localizedDescription)",
            level: .error
          )
          continuation.finish(throwing: error)
        }
      }
    }
  }

private func parseEvent(from jsonString: String) -> OpenCodeEvent? {
  guard let jsonData = jsonString.data(using: .utf8) else {
    return nil
  }

  let decoder = JSONDecoder()

  if let event = tryParseSessionUpdated(from: jsonData) ?? tryParseSessionDeleted(from: jsonData) ?? tryParseMessageUpdated(from: jsonData) ?? tryParseMessagePartUpdated(from: jsonData) {
    return event
  } else {
    log("OpenCode API: Received unknown event: \(jsonString)", level: .warning)
    return .unknown(jsonString)
  }
}

private func tryParseSessionUpdated(from jsonData: Data) -> OpenCodeEvent? {
  guard let sessionUpdated = try? JSONDecoder().decode(
    Components.Schemas.Event_period_session_period_updated.self,
    from: jsonData
  ) else { return nil }

  let sessionData = sessionUpdated.properties.info
  let session = OpenCodeSession(
    id: sessionData.id,
    createdAt: Date(timeIntervalSince1970: sessionData.time.created),
    updatedAt: Date(timeIntervalSince1970: sessionData.time.updated),
    isActive: true,
    title: sessionData.title
  )
  log("OpenCode API: Received session.updated event for session: \(session.id)")
  return .sessionUpdated(session)
}

private func tryParseSessionDeleted(from jsonData: Data) -> OpenCodeEvent? {
  guard let sessionDeleted = try? JSONDecoder().decode(
    Components.Schemas.Event_period_session_period_deleted.self,
    from: jsonData
  ) else { return nil }

  let sessionID = sessionDeleted.properties.info.id
  log("OpenCode API: Received session.deleted event for session: \(sessionID)")
  return .sessionDeleted(sessionID)
}

private func tryParseMessageUpdated(from jsonData: Data) -> OpenCodeEvent? {
  guard let messageUpdated = try? JSONDecoder().decode(
    Components.Schemas.Event_period_message_period_updated.self,
    from: jsonData
  ) else { return nil }

  let messageData = messageUpdated.properties.info
  let message = OpenCodeMessage(
    id: messageData.id,
    sessionID: messageData.sessionID,
    parts: messageData.parts.map { partData in
      switch partData.type {
      case "text":
        return .text(partData.content ?? "", id: partData.id)
      case "reasoning":
        return .reasoning(partData.content ?? "", id: partData.id)
      default:
        return .text(partData.content ?? "", id: partData.id)
      }
    },
    timestamp: Date(timeIntervalSince1970: messageData.time),
    role: MessageRole(rawValue: messageData.role) ?? .assistant,
    modelID: messageData.modelID,
    providerID: messageData.providerID
  )
  log("OpenCode API: Received message.updated for \(message.id)")
  return .messageUpdated(message)
}

private func tryParseMessagePartUpdated(from jsonData: Data) -> OpenCodeEvent? {
  guard let messagePartUpdated = try? JSONDecoder().decode(
    Components.Schemas.Event_period_message_period_part_period_updated.self,
    from: jsonData
  ) else { return nil }

  let partData = messagePartUpdated.properties.part
  let part: MessagePart
  switch partData.type {
  case "text":
    part = .text(partData.content ?? "", id: partData.id)
  case "reasoning":
    part = .reasoning(partData.content ?? "", id: partData.id)
  default:
    part = .text(partData.content ?? "", id: partData.id)
  }
  log("OpenCode API: Received message.part.updated for session \(messagePartUpdated.properties.sessionID), message \(messagePartUpdated.properties.messageID), part \(partData.id)")
  return .messagePartUpdated(
    sessionID: messagePartUpdated.properties.sessionID,
    messageID: messagePartUpdated.properties.messageID,
    partID: partData.id,
    part: part
  )
}
}

// MARK: - Project Operations

extension LiveOpenCodeAPIClient {
  public func listProjects() async throws -> [OpenCodeProject] {
    log("OpenCode API: Listing projects")

    let input = Operations.project_period_list.Input()

    do {
      let response = try await client.project_period_list(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case let .json(projectList):
          let projects = projectList.map { projectData in
            OpenCodeProject(
              id: projectData.id,
              name: projectData.id, // Use ID as name for now
              path: projectData.worktree,
              type: projectData.vcs?.rawValue
            )
          }
          log("OpenCode API: Successfully retrieved \(projects.count) projects")
          return projects
        }
      case let .undocumented(statusCode, _):
        log("OpenCode API: List projects failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to list projects: \(statusCode)")
      }
    } catch {
      log("OpenCode API: List projects failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  public func getCurrentProject() async throws -> OpenCodeProject? {
    log("OpenCode API: Getting current project")

    let input = Operations.project_period_current.Input()

    do {
      let response = try await client.project_period_current(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case let .json(projectData):
          let project = OpenCodeProject(
            id: projectData.id,
            name: projectData.id, // Use ID as name for now
            path: projectData.worktree,
            type: projectData.vcs?.rawValue
          )
          log("OpenCode API: Successfully retrieved current project: \(project.id)")
          return project
        }
      case .undocumented:
        log("OpenCode API: No current project found")
        return nil // Current project might not exist
      }
    } catch {
      log("OpenCode API: Get current project failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

}
