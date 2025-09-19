import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import HTTPTypes
import Dependencies

// MARK: - Protocol Definition

package protocol OpenCodeAPIClientProtocol: Sendable {
  // Session Management
  func listSessions() async throws -> [OpenCodeSession]
  func createSession() async throws -> OpenCodeSession
  func deleteSession(id: String) async throws
  func getSession(id: String) async throws -> OpenCodeSession

  // Project Operations
  func listProjects() async throws -> [OpenCodeProject]
  func getCurrentProject() async throws -> OpenCodeProject?

  // Message Operations
  func sendMessage(sessionID: String, parts: [MessagePart]) async throws -> OpenCodeMessage
  func getMessages(sessionID: String) async throws -> [OpenCodeMessage]
  func getMessage(sessionID: String, messageID: String) async throws -> OpenCodeMessage

  // Command Operations
  func sendCommand(sessionID: String, command: String, arguments: [String]) async throws -> OpenCodeMessage
  func runShellCommand(sessionID: String, command: String) async throws -> OpenCodeMessage

  // Configuration
  func getConfig() async throws -> OpenCodeConfig
  func listProviders() async throws -> OpenCodeProviders
}

// MARK: - Domain Models

package struct OpenCodeSession: Equatable, Identifiable, Sendable {
  package let id: String
  package let createdAt: Date
  package let updatedAt: Date
  package let isActive: Bool

  package init(id: String, createdAt: Date, updatedAt: Date, isActive: Bool = true) {
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.isActive = isActive
  }
}

package struct OpenCodeProject: Equatable, Identifiable, Sendable {
  package let id: String
  package let name: String
  package let path: String
  package let type: String?

  package init(id: String, name: String, path: String, type: String? = nil) {
    self.id = id
    self.name = name
    self.path = path
    self.type = type
  }
}

package struct OpenCodeMessage: Equatable, Identifiable, Sendable {
  package let id: String
  package let sessionID: String
  package let parts: [MessagePart]
  package let timestamp: Date
  package let role: MessageRole

  package init(id: String, sessionID: String, parts: [MessagePart], timestamp: Date, role: MessageRole) {
    self.id = id
    self.sessionID = sessionID
    self.parts = parts
    self.timestamp = timestamp
    self.role = role
  }
}

package enum MessageRole: String, Equatable, Sendable, CaseIterable {
  case user
  case assistant
  case system
}

package enum MessagePart: Equatable, Sendable {
  case text(String)
  case file(path: String, content: String)
  case agent(type: String, result: String)
  case tool(name: String, input: String, output: String)
}

package struct OpenCodeConfig: Equatable, Sendable {
  package let version: String
  package let environment: String
  package let features: [String]

  package init(version: String, environment: String, features: [String]) {
    self.version = version
    self.environment = environment
    self.features = features
  }
}

package struct OpenCodeProviders: Equatable, Sendable {
  package let providers: [String: [String: String]]
  package let defaultProvider: String

  package init(providers: [String: [String: String]], defaultProvider: String) {
    self.providers = providers
    self.defaultProvider = defaultProvider
  }
}

// MARK: - Error Handling

package enum OpenCodeAPIError: Error, Equatable {
  case badRequest(String? = nil)
  case unauthorized(String? = nil)
  case notFound(String? = nil)
  case serverError(String? = nil)
  case networkError(String)
  case decodingError(String)
  case invalidURL(String)
  case sessionNotFound(String)
  case projectNotFound(String)
  case messageNotFound(String)
}

extension OpenCodeAPIError: LocalizedError {
  package var errorDescription: String? {
    switch self {
    case let .badRequest(message):
      return "Bad request" + (message.map { ": \($0)" } ?? "")
    case let .unauthorized(message):
      return "Unauthorized" + (message.map { ": \($0)" } ?? "")
    case let .notFound(message):
      return "Not found" + (message.map { ": \($0)" } ?? "")
    case let .serverError(message):
      return "Server error" + (message.map { ": \($0)" } ?? "")
    case let .networkError(message):
      return "Network error: \(message)"
    case let .decodingError(message):
      return "Decoding error: \(message)"
    case let .invalidURL(url):
      return "Invalid URL: \(url)"
    case let .sessionNotFound(id):
      return "Session not found: \(id)"
    case let .projectNotFound(id):
      return "Project not found: \(id)"
    case let .messageNotFound(id):
      return "Message not found: \(id)"
    }
  }
}

// MARK: - Test Implementation

package struct MockOpenCodeAPIClient: OpenCodeAPIClientProtocol {
  package var sessions: [OpenCodeSession] = []
  package var projects: [OpenCodeProject] = []
  package var messages: [String: [OpenCodeMessage]] = [:]

  package init() {}

  package func listSessions() async throws -> [OpenCodeSession] {
    return sessions
  }

  package func createSession() async throws -> OpenCodeSession {
    let session = OpenCodeSession(
      id: UUID().uuidString,
      createdAt: Date(),
      updatedAt: Date()
    )
    return session
  }

  package func deleteSession(id: String) async throws {
    // Mock implementation
  }

  package func getSession(id: String) async throws -> OpenCodeSession {
    guard let session = sessions.first(where: { $0.id == id }) else {
      throw OpenCodeAPIError.sessionNotFound(id)
    }
    return session
  }

  package func listProjects() async throws -> [OpenCodeProject] {
    return projects
  }

  package func getCurrentProject() async throws -> OpenCodeProject? {
    return projects.first
  }

  package func sendMessage(sessionID: String, parts: [MessagePart]) async throws -> OpenCodeMessage {
    let message = OpenCodeMessage(
      id: UUID().uuidString,
      sessionID: sessionID,
      parts: parts,
      timestamp: Date(),
      role: .user
    )
    return message
  }

  package func getMessages(sessionID: String) async throws -> [OpenCodeMessage] {
    return messages[sessionID] ?? []
  }

  package func getMessage(sessionID: String, messageID: String) async throws -> OpenCodeMessage {
    guard let sessionMessages = messages[sessionID],
          let message = sessionMessages.first(where: { $0.id == messageID }) else {
      throw OpenCodeAPIError.messageNotFound(messageID)
    }
    return message
  }

  package func sendCommand(sessionID: String, command: String, arguments: [String]) async throws -> OpenCodeMessage {
    let message = OpenCodeMessage(
      id: UUID().uuidString,
      sessionID: sessionID,
      parts: [.text("\(command) \(arguments.joined(separator: " "))")],
      timestamp: Date(),
      role: .user
    )
    return message
  }

  package func runShellCommand(sessionID: String, command: String) async throws -> OpenCodeMessage {
    let message = OpenCodeMessage(
      id: UUID().uuidString,
      sessionID: sessionID,
      parts: [.text("$ \(command)")],
      timestamp: Date(),
      role: .user
    )
    return message
  }

  package func getConfig() async throws -> OpenCodeConfig {
    return OpenCodeConfig(
      version: "0.10.1",
      environment: "development",
      features: ["sessions", "projects", "chat"]
    )
  }

  package func listProviders() async throws -> OpenCodeProviders {
    return OpenCodeProviders(
      providers: ["openai": ["gpt-4": "GPT-4"]],
      defaultProvider: "openai"
    )
  }
}

// MARK: - Dependency Injection

package enum OpenCodeAPIClientKey: DependencyKey, TestDependencyKey {
  package static let liveValue: OpenCodeAPIClientProtocol = MockOpenCodeAPIClient() // Default to mock
  package static let testValue: OpenCodeAPIClientProtocol = MockOpenCodeAPIClient()
}

extension DependencyValues {
  package var openCodeAPI: OpenCodeAPIClientProtocol {
    get { self[OpenCodeAPIClientKey.self] }
    set { self[OpenCodeAPIClientKey.self] = newValue }
  }
}
