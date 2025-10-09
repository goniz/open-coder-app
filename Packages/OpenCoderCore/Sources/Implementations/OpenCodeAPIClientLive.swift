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
    log("OpenCode API: Listing sessions from \(configuration.serverURL)", level: .debug)

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
              createdAt: Date(timeIntervalSince1970: sessionData.time.created / 1000),
              updatedAt: Date(timeIntervalSince1970: sessionData.time.updated / 1000),
              isActive: true, // Assume active if listed
              title: sessionData.title
            )
          }
          log("OpenCode API: Successfully retrieved \(sessions.count) sessions", level: .debug)
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
            createdAt: Date(timeIntervalSince1970: sessionData.time.created / 1000),
            updatedAt: Date(timeIntervalSince1970: sessionData.time.updated / 1000),
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
          createdAt: Date(timeIntervalSince1970: sessionData.time.created / 1000),
          updatedAt: Date(timeIntervalSince1970: sessionData.time.updated / 1000),
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
        var parser = SSEEventParser()

        do {
          for try await chunk in httpBody {
            guard let chunkString = String(bytes: chunk, encoding: .utf8) else {
              continue
            }

            parser.ingest(chunkString) { eventJSON in
              emitEvent(from: eventJSON, continuation: continuation)
            }
          }

          parser.finish { eventJSON in
            emitEvent(from: eventJSON, continuation: continuation)
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
