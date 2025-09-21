import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import HTTPTypes
import DependencyClients
import Dependencies
import Models

package struct LiveOpenCodeAPIClient: OpenCodeAPIClientProtocol {
  private let client: Client
  private let configuration: OpenCodeConfiguration

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
    let input = Operations.session_period_list.Input()
    let response = try await client.session_period_list(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(sessionList):
        return sessionList.map { sessionData in
          // Convert API response to domain model using actual properties
          return OpenCodeSession(
            id: sessionData.id,
            createdAt: Date(), // API doesn't provide timestamps in current schema
            updatedAt: Date(),
            isActive: true // Assume active if listed
          )
        }
      }
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Unexpected status code: \(statusCode)")
    }
  }

  package func createSession() async throws -> OpenCodeSession {
    let input = Operations.session_period_create.Input()
    let response = try await client.session_period_create(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(sessionData):
        return OpenCodeSession(
          id: sessionData.id,
          createdAt: Date(),
          updatedAt: Date(),
          isActive: true
        )
      }
    case .badRequest:
      throw OpenCodeAPIError.badRequest("Failed to create session")
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Failed to create session: \(statusCode)")
    }
  }

  package func deleteSession(id: String) async throws {
    let input = Operations.session_period_delete.Input(path: .init(id: id))
    let response = try await client.session_period_delete(input)

    switch response {
    case .ok:
      return
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Failed to delete session: \(statusCode)")
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
          isActive: true
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
    let input = Operations.project_period_list.Input()
    let response = try await client.project_period_list(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(projectList):
        return projectList.map { projectData in
          OpenCodeProject(
            id: projectData.id,
            name: projectData.id, // Use ID as name for now
            path: projectData.worktree,
            type: projectData.vcs?.rawValue
          )
        }
      }
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Failed to list projects: \(statusCode)")
    }
  }

  package func getCurrentProject() async throws -> OpenCodeProject? {
    let input = Operations.project_period_current.Input()
    let response = try await client.project_period_current(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(projectData):
        return OpenCodeProject(
          id: projectData.id,
          name: projectData.id, // Use ID as name for now
          path: projectData.worktree,
          type: projectData.vcs?.rawValue
        )
      }
    case .undocumented:
      return nil // Current project might not exist
    }
  }

}

// MARK: - Message Operations

extension LiveOpenCodeAPIClient {
  package func sendMessage(sessionID: String, parts: [MessagePart]) async throws -> OpenCodeMessage {
    // For now, create a simple text message
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

    // Create a text part input
    let textPart = Components.Schemas.TextPartInput(
      id: nil,
      _type: .text,
      text: textContent,
      synthetic: nil,
      time: nil
    )

    // Create the proper parts payload
    let partPayload = Operations.session_period_prompt.Input.Body.jsonPayload.partsPayloadPayload(
      value1: textPart,
      value2: nil,
      value3: nil
    )

    let requestBody = Operations.session_period_prompt.Input.Body.json(
      .init(parts: [partPayload])
    )

    let input = Operations.session_period_prompt.Input(
      path: .init(id: sessionID),
      body: requestBody
    )

    let response = try await client.session_period_prompt(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case .json:
        // Create a simple response message
        return OpenCodeMessage(
          id: UUID().uuidString, // Generate ID for now
          sessionID: sessionID,
          parts: [.text("Message sent successfully")],
          timestamp: Date(),
          role: .assistant
        )
      }
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Failed to send message: \(statusCode)")
    }
  }

  package func getMessages(sessionID: String) async throws -> [OpenCodeMessage] {
    let input = Operations.session_period_messages.Input(path: .init(id: sessionID))
    let response = try await client.session_period_messages(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(messageList):
        return messageList.indices.map { index in
          // Create basic messages for now
          return OpenCodeMessage(
            id: "message-\(index)",
            sessionID: sessionID,
            parts: [.text("Message from session")],
            timestamp: Date(),
            role: index % 2 == 0 ? .user : .assistant
          )
        }
      }
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Failed to get messages: \(statusCode)")
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

// MARK: - Command Operations

extension LiveOpenCodeAPIClient {
  package func sendCommand(sessionID: String, command: String, arguments: [String]) async throws -> OpenCodeMessage {
    let requestBody = Operations.session_period_command.Input.Body.json(
      .init(arguments: arguments.joined(separator: " "), command: command)
    )

    let input = Operations.session_period_command.Input(
      path: .init(id: sessionID),
      body: requestBody
    )

    let response = try await client.session_period_command(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case .json:
        return OpenCodeMessage(
          id: UUID().uuidString,
          sessionID: sessionID,
          parts: [.text("Command executed: \(command)")],
          timestamp: Date(),
          role: .assistant
        )
      }
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Failed to send command: \(statusCode)")
    }
  }

  package func runShellCommand(sessionID: String, command: String) async throws -> OpenCodeMessage {
    let requestBody = Operations.session_period_shell.Input.Body.json(
      .init(agent: "shell", command: command)
    )

    let input = Operations.session_period_shell.Input(
      path: .init(id: sessionID),
      body: requestBody
    )

    let response = try await client.session_period_shell(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case .json:
        return OpenCodeMessage(
          id: UUID().uuidString,
          sessionID: sessionID,
          parts: [.text("Shell command executed: \(command)")],
          timestamp: Date(),
          role: .assistant
        )
      }
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Failed to run shell command: \(statusCode)")
    }
  }

}

// MARK: - Configuration

extension LiveOpenCodeAPIClient {
  package func getConfig() async throws -> OpenCodeConfig {
    let input = Operations.config_period_get.Input()
    let response = try await client.config_period_get(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case .json:
        // Return basic config for now
        return OpenCodeConfig(
          version: "0.10.1",
          environment: "development",
          features: ["sessions", "projects", "chat"]
        )
      }
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Failed to get config: \(statusCode)")
    }
  }

  package func listProviders() async throws -> OpenCodeProviders {
    let input = Operations.config_period_providers.Input()
    let response = try await client.config_period_providers(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(providersData):
        // Convert providers array to dictionary format expected by domain model
        var providerDict: [String: [String: String]] = [:]
        for provider in providersData.providers {
          // For now, create a simple mapping
          providerDict[provider.id] = [provider.id: provider.id]
        }

        return OpenCodeProviders(
          providers: providerDict,
          defaultProvider: providersData.providers.first?.id ?? "openai"
        )
      }
    case let .undocumented(statusCode, _):
      throw OpenCodeAPIError.serverError("Failed to list providers: \(statusCode)")
    }
  }
}

extension OpenCodeAPIClientFactoryKey {
  package static let liveValue = OpenCodeAPIClientFactory { configuration in
    LiveOpenCodeAPIClient(configuration: configuration)
  }
}
