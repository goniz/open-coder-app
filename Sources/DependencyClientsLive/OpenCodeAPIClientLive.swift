import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import HTTPTypes
import DependencyClients
import Dependencies
import Models

package struct LiveOpenCodeAPIClient: OpenCodeAPIClientProtocol {
  package let client: Client
  package let configuration: OpenCodeConfiguration

  package init(
    configuration: OpenCodeConfiguration = .development,
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
  package func listSessions() async throws -> [OpenCodeSession] {
    log("🔗 OpenCode API: Listing sessions from \(configuration.serverURL)")

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
              createdAt: Date(), // API doesn't provide timestamps in current schema
              updatedAt: Date(),
              isActive: true, // Assume active if listed
              title: nil // API doesn't provide title, will use formatted date
            )
          }
          log("✅ OpenCode API: Successfully retrieved \(sessions.count) sessions")
          return sessions
        }
      case let .undocumented(statusCode, _):
        log("❌ OpenCode API: List sessions failed with undocumented status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Unexpected status code: \(statusCode)")
      }
    } catch {
      log("❌ OpenCode API: List sessions failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  package func createSession() async throws -> OpenCodeSession {
    log("🔗 OpenCode API: Creating new session")

    let input = Operations.session_period_create.Input()

    do {
      let response = try await client.session_period_create(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case let .json(sessionData):
          let session = OpenCodeSession(
            id: sessionData.id,
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            title: nil
          )
          log("✅ OpenCode API: Successfully created session with ID: \(session.id)")
          return session
        }
      case .badRequest:
        log("❌ OpenCode API: Create session failed - bad request", level: .error)
        throw OpenCodeAPIError.badRequest("Failed to create session")
      case let .undocumented(statusCode, _):
        log("❌ OpenCode API: Create session failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to create session: \(statusCode)")
      }
    } catch {
      log("❌ OpenCode API: Create session failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  package func deleteSession(id: String) async throws {
    log("🔗 OpenCode API: Deleting session: \(id)")

    let input = Operations.session_period_delete.Input(path: .init(id: id))

    do {
      let response = try await client.session_period_delete(input)

      switch response {
      case .ok:
        log("✅ OpenCode API: Successfully deleted session: \(id)")
        return
      case let .undocumented(statusCode, _):
        log("❌ OpenCode API: Delete session failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to delete session: \(statusCode)")
      }
    } catch {
      log("❌ OpenCode API: Delete session failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  package func getSession(id: String) async throws -> OpenCodeSession {
    let input = Operations.session_period_get.Input(path: .init(id: id))
    let response = try await client.session_period_get(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(sessionData):
        return OpenCodeSession(
          id: sessionData.id,
          createdAt: Date(),
          updatedAt: Date(),
          isActive: true,
          title: nil
        )
      }
    case .undocumented:
      throw OpenCodeAPIError.sessionNotFound(id)
    }
  }

}

// MARK: - Project Operations

extension LiveOpenCodeAPIClient {
  package func listProjects() async throws -> [OpenCodeProject] {
    log("🔗 OpenCode API: Listing projects")

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
          log("✅ OpenCode API: Successfully retrieved \(projects.count) projects")
          return projects
        }
      case let .undocumented(statusCode, _):
        log("❌ OpenCode API: List projects failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to list projects: \(statusCode)")
      }
    } catch {
      log("❌ OpenCode API: List projects failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  package func getCurrentProject() async throws -> OpenCodeProject? {
    log("🔗 OpenCode API: Getting current project")

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
          log("✅ OpenCode API: Successfully retrieved current project: \(project.id)")
          return project
        }
      case .undocumented:
        log("ℹ️ OpenCode API: No current project found")
        return nil // Current project might not exist
      }
    } catch {
      log("❌ OpenCode API: Get current project failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

}

// MARK: - Message Operations

extension LiveOpenCodeAPIClient {
  package func sendMessage(sessionID: String, parts: [MessagePart]) async throws -> OpenCodeMessage {
    log("🔗 OpenCode API: Sending message to session: \(sessionID)")

    let requestBody = createSendMessageRequestBody(from: parts)
    let input = Operations.session_period_prompt.Input(path: .init(id: sessionID), body: requestBody)

    do {
      let response = try await client.session_period_prompt(input)
      return try handleSendMessageResponse(response, sessionID: sessionID)
    } catch {
      log("❌ OpenCode API: Send message failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  private func createSendMessageRequestBody(from parts: [MessagePart]) -> Operations.session_period_prompt.Input.Body {
    let textContent = parts.compactMap { part in
      switch part {
      case let .text(content):
        return content
      case let .file(path, content):
        return "File: \(path)\n\(content)"
      case let .agent(type, result):
        return "Agent: \(type)\n\(result)"
      case let .tool(name, input, output):
        return "Tool: \(name), Input: \(input), Output: \(output)"
      }
    }.joined(separator: "\n")

    let textPart = Components.Schemas.TextPartInput(
      id: nil, _type: .text, text: textContent, synthetic: nil, time: nil
    )

    let partPayload = Operations.session_period_prompt.Input.Body.jsonPayload.partsPayloadPayload(
      value1: textPart, value2: nil, value3: nil
    )

    return Operations.session_period_prompt.Input.Body.json(.init(parts: [partPayload]))
  }

  private func handleSendMessageResponse(
    _ response: Operations.session_period_prompt.Output,
    sessionID: String
  ) throws -> OpenCodeMessage {
    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case .json:
        let message = OpenCodeMessage(
          id: UUID().uuidString,
          sessionID: sessionID,
          parts: [.text("Message sent successfully")],
          timestamp: Date(),
          role: .assistant
        )
        log("✅ OpenCode API: Successfully sent message to session: \(sessionID)")
        return message
      }
    case let .undocumented(statusCode, _):
      log("❌ OpenCode API: Send message failed with status code: \(statusCode)", level: .error)
      throw OpenCodeAPIError.serverError("Failed to send message: \(statusCode)")
    }
  }

  package func getMessages(sessionID: String) async throws -> [OpenCodeMessage] {
    log("🔗 OpenCode API: Getting messages from session: \(sessionID)")

    let input = Operations.session_period_messages.Input(path: .init(id: sessionID))

    do {
      let response = try await client.session_period_messages(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case let .json(messageList):
          let messages = messageList.indices.map { index in
            // Create basic messages for now
            return OpenCodeMessage(
              id: "message-\(index)",
              sessionID: sessionID,
              parts: [.text("Message from session")],
              timestamp: Date(),
              role: index % 2 == 0 ? .user : .assistant
            )
          }
          log("✅ OpenCode API: Successfully retrieved \(messages.count) messages from session: \(sessionID)")
          return messages
        }
      case let .undocumented(statusCode, _):
        log("❌ OpenCode API: Get messages failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to get messages: \(statusCode)")
      }
    } catch {
      log("❌ OpenCode API: Get messages failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  package func getMessage(sessionID: String, messageID: String) async throws -> OpenCodeMessage {
    let input = Operations.session_period_message.Input(
      path: .init(id: sessionID, messageID: messageID)
    )
    let response = try await client.session_period_message(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case .json:
        return OpenCodeMessage(
          id: messageID,
          sessionID: sessionID,
          parts: [.text("Single message")],
          timestamp: Date(),
          role: .assistant
        )
      }
    case .undocumented:
      throw OpenCodeAPIError.messageNotFound(messageID)
    }
  }

}


