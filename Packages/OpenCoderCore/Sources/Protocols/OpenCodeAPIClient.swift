import Foundation
import Models
import OpenAPIGenerated
import Dependencies

// MARK: - Protocol Definition

public protocol OpenCodeAPIClientProtocol: Sendable {
  // Session Management
  func listSessions() async throws -> [OpenCodeSession]
  func createSession() async throws -> OpenCodeSession
  func deleteSession(id: String) async throws
  func getSession(id: String) async throws -> OpenCodeSession

  // Project Operations
  func listProjects() async throws -> [OpenCodeProject]
  func getCurrentProject() async throws -> OpenCodeProject?

  // Message Operations
  func sendMessage(
    sessionID: String,
    parts: [MessagePart],
    providerID: String?,
    modelID: String?
  ) async throws -> OpenCodeMessage
  func getMessages(sessionID: String) async throws -> [OpenCodeMessage]
  func getMessage(sessionID: String, messageID: String) async throws -> OpenCodeMessage

  // Command Operations
  func sendCommand(sessionID: String, command: String, arguments: [String]) async throws -> OpenCodeMessage
  func runShellCommand(sessionID: String, command: String) async throws -> OpenCodeMessage

  // Configuration
  func getConfig() async throws -> OpenCodeConfig
  func listProviders() async throws -> OpenCodeProviders

  // Event Streaming
  func subscribeToEvents() async throws -> AsyncThrowingStream<OpenCodeEvent, Error>

  // File Operations
  func findFiles(query: String, directory: String?) async throws -> [FileSuggestion]
  func readFile(path: String, directory: String?) async throws -> String
}

// MARK: - Event Models

public enum OpenCodeEvent: Equatable, Sendable {
  case sessionUpdated(OpenCodeSession)
  case sessionDeleted(String)
  case messageReceived(OpenCodeMessage)
  case messageUpdated(OpenCodeMessage)
  case messagePartUpdated(sessionID: String, messageID: String, partID: String, part: MessagePart)
  case unknown(String)
}

// MARK: - Domain Models

public struct OpenCodeSession: Equatable, Identifiable, Sendable {
  public let id: String
  public let createdAt: Date
  public let updatedAt: Date
  public let isActive: Bool
  public let title: String?

  public init(id: String, createdAt: Date, updatedAt: Date, isActive: Bool = true, title: String? = nil) {
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.isActive = isActive
    self.title = title
  }

  public var displayTitle: String {
    return title ?? DateFormatter.sessionTitle.string(from: createdAt)
  }
}

private extension DateFormatter {
  static let sessionTitle: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}

public struct OpenCodeProject: Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let path: String
  public let type: String?

  public init(id: String, name: String, path: String, type: String? = nil) {
    self.id = id
    self.name = name
    self.path = path
    self.type = type
  }
}

public struct OpenCodeMessage: Equatable, Identifiable, Sendable {
  public let id: String
  public let sessionID: String
  public let parts: [MessagePart]
  public let timestamp: Date
  public let role: MessageRole
  public let modelID: String?
  public let providerID: String?

  public init(
    id: String,
    sessionID: String,
    parts: [MessagePart],
    timestamp: Date,
    role: MessageRole,
    modelID: String? = nil,
    providerID: String? = nil
  ) {
    self.id = id
    self.sessionID = sessionID
    self.parts = parts
    self.timestamp = timestamp
    self.role = role
    self.modelID = modelID
    self.providerID = providerID
  }

  public var displayModelName: String {
    guard let modelID = modelID else { return "Assistant" }

    // Extract short model name from common patterns
    let shortModelName = modelID
      .replacingOccurrences(of: "gpt-", with: "")
      .replacingOccurrences(of: "claude-", with: "")
      .replacingOccurrences(of: "anthropic.", with: "")
      .replacingOccurrences(of: "openai/", with: "")
      .replacingOccurrences(of: "google/", with: "")
      .replacingOccurrences(of: "-preview", with: "")
      .replacingOccurrences(of: "-latest", with: "")

    return shortModelName.isEmpty ? "Assistant" : shortModelName.uppercased()
  }
}

public enum MessageRole: String, Equatable, Sendable, CaseIterable {
  case user
  case assistant
  case system
}

public enum MessagePart: Equatable, Sendable {
  case text(String, id: String?)
  case reasoning(String, id: String?)
  case file(path: String, content: String, id: String?)
  case structuredFile(
    path: String,
    url: String,
    mimeType: String,
    displayText: String,
    startIndex: Int,
    endIndex: Int,
    id: String?
  )
  case agent(type: String, result: String, id: String?)
  case tool(name: String, input: String, output: String, error: String?, id: String?)
  case patch(hash: String, files: [String], id: String?)
  case stepStart(id: String?)
  case stepFinish(cost: Double, inputTokens: Double, outputTokens: Double, id: String?)
  case snapshot(content: String, id: String?)
}

public struct OpenCodeConfig: Equatable, Sendable {
  public let version: String
  public let environment: String
  public let features: [String]

  public init(version: String, environment: String, features: [String]) {
    self.version = version
    self.environment = environment
    self.features = features
  }
}

// MARK: - Error Handling

public enum OpenCodeAPIError: Error, Equatable, Sendable {
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
  public var errorDescription: String? {
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

public struct MockOpenCodeAPIClient: OpenCodeAPIClientProtocol, Sendable {
  public var sessions: [OpenCodeSession] = []
  public var projects: [OpenCodeProject] = []
  public var messages: [String: [OpenCodeMessage]] = [:]

  public init() {
    // Add some default sessions for development
    self.sessions = [
      OpenCodeSession(
        id: "mock-session-1",
        createdAt: Date().addingTimeInterval(-3600), // 1 hour ago
        updatedAt: Date().addingTimeInterval(-1800), // 30 minutes ago
        isActive: true,
        title: "Development Session"
      ),
      OpenCodeSession(
        id: "mock-session-2",
        createdAt: Date().addingTimeInterval(-7200), // 2 hours ago
        updatedAt: Date().addingTimeInterval(-900), // 15 minutes ago
        isActive: true,
        title: "Testing Session"
      )
    ]
  }

  private func log(_ message: String, level: LogLevel = .info) {
    Task { @MainActor in
      AppLogger.shared.log(message, level: level, category: .api)
    }
  }

  public func listSessions() async throws -> [OpenCodeSession] {
    log("🧪 Mock API: Listing sessions (mock)")
    log("✅ Mock API: Returned \(sessions.count) mock sessions")
    return sessions
  }

  public func createSession() async throws -> OpenCodeSession {
    log("🧪 Mock API: Creating session (mock)")
    let session = OpenCodeSession(
      id: UUID().uuidString,
      createdAt: Date(),
      updatedAt: Date(),
      title: "New Session"
    )
    log("✅ Mock API: Created mock session with ID: \(session.id)")
    return session
  }

  public func deleteSession(id: String) async throws {
    // Mock implementation
  }

  public func getSession(id: String) async throws -> OpenCodeSession {
    guard let session = sessions.first(where: { $0.id == id }) else {
      throw OpenCodeAPIError.sessionNotFound(id)
    }
    return session
  }

  public func listProjects() async throws -> [OpenCodeProject] {
    return projects
  }

  public func getCurrentProject() async throws -> OpenCodeProject? {
    return projects.first
  }

  public func sendMessage(
    sessionID: String,
    parts: [MessagePart],
    providerID: String?,
    modelID: String?
  ) async throws -> OpenCodeMessage {
    let message = OpenCodeMessage(
      id: UUID().uuidString,
      sessionID: sessionID,
      parts: parts,
      timestamp: Date(),
      role: .user,
      modelID: modelID,
      providerID: providerID
    )
    return message
  }

  public func getMessages(sessionID: String) async throws -> [OpenCodeMessage] {
    return messages[sessionID] ?? []
  }

  public func getMessage(sessionID: String, messageID: String) async throws -> OpenCodeMessage {
    guard let sessionMessages = messages[sessionID],
          let message = sessionMessages.first(where: { $0.id == messageID }) else {
      throw OpenCodeAPIError.messageNotFound(messageID)
    }
    return message
  }

  public func sendCommand(sessionID: String, command: String, arguments: [String]) async throws -> OpenCodeMessage {
    let message = OpenCodeMessage(
      id: UUID().uuidString,
      sessionID: sessionID,
      parts: [.text("\(command) \(arguments.joined(separator: " "))", id: nil)],
      timestamp: Date(),
      role: .user,
      modelID: nil,
      providerID: nil
    )
    return message
  }

  public func runShellCommand(sessionID: String, command: String) async throws -> OpenCodeMessage {
    let message = OpenCodeMessage(
      id: UUID().uuidString,
      sessionID: sessionID,
      parts: [.text("$ \(command)", id: nil)],
      timestamp: Date(),
      role: .user,
      modelID: nil,
      providerID: nil
    )
    return message
  }

  public func getConfig() async throws -> OpenCodeConfig {
    return OpenCodeConfig(
      version: "0.10.1",
      environment: "development",
      features: ["sessions", "projects", "chat"]
    )
  }

  public func listProviders() async throws -> OpenCodeProviders {
    return OpenCodeProviders(
      providers: ["openai": OpenCodeProviderInfo(name: "OpenAI", models: ["gpt-4": "GPT-4"])],
      defaultModelsByProvider: ["openai": "gpt-4"],
      primaryDefaultProviderID: "openai",
      primaryDefaultModelID: "gpt-4"
    )
  }

public func subscribeToEvents() async throws -> AsyncThrowingStream<OpenCodeEvent, Error> {
  return AsyncThrowingStream { continuation in
    Task {
      // Simulate events for testing
      try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
      let sampleMessage = OpenCodeMessage(
        id: "mock-message-1",
        sessionID: "mock-session-1",
        parts: [.text("Updated message content", id: "part1")],
        timestamp: Date(),
        role: .assistant
      )
      continuation.yield(.messageUpdated(sampleMessage))

      try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
      continuation.yield(.messagePartUpdated(
        sessionID: "mock-session-1",
        messageID: "mock-message-1",
        partID: "part2",
        part: .text("Appended part", id: "part2")
      ))

      try? await Task.sleep(nanoseconds: 1_000_000_000)
      continuation.finish()
    }
  }
}

  // MARK: - File Operations (Mock)

  public func findFiles(query: String, directory: String?) async throws -> [FileSuggestion] {
    let samples = [
      "README.md",
      "Sources/App/AppDelegate.swift",
      "Sources/Feature/Chat/ChatView.swift"
    ].filter { $0.localizedCaseInsensitiveContains(query) }

    return samples.map { path in
      let name = (path as NSString).lastPathComponent
      let ext = (path as NSString).pathExtension
      let type = ext.isEmpty ? nil : ext
      return FileSuggestion(path: path, name: name, type: type)
    }
  }

  public func readFile(path: String, directory: String?) async throws -> String {
    // Return a short mock content
    return "// Mock content for \(path)\nprint(\"Hello from mock!\")\n"
  }
}

// MARK: - Dependency Injection

public enum OpenCodeAPIClientKey: DependencyKey, TestDependencyKey, Sendable {
  public static let liveValue: OpenCodeAPIClientProtocol = MockOpenCodeAPIClient() // Default to mock
  public static let testValue: OpenCodeAPIClientProtocol = MockOpenCodeAPIClient()
}

extension DependencyValues {
  public var openCodeAPI: OpenCodeAPIClientProtocol {
    get { self[OpenCodeAPIClientKey.self] }
    set { self[OpenCodeAPIClientKey.self] = newValue }
  }
}
