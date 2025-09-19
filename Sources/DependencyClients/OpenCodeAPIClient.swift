import ComposableArchitecture
import Foundation

@DependencyClient
public struct OpenCodeAPIClient: Sendable {
  public var listProjects: @Sendable (_ directory: String?) async throws -> [Project]
  public var getCurrentProject: @Sendable (_ directory: String?) async throws -> Project
  public var getConfig: @Sendable (_ directory: String?) async throws -> Config
  public var getPath: @Sendable (_ directory: String?) async throws -> Path
  public var listSessions: @Sendable (_ directory: String?) async throws -> [Session]
  public var createSession: @Sendable (
    _ directory: String?, _ parentID: String?, _ title: String?
  ) async throws -> Session
  public var getSession: @Sendable (_ id: String, _ directory: String?) async throws -> Session
  public var deleteSession: @Sendable (_ id: String, _ directory: String?) async throws -> Bool
  public var updateSession: @Sendable (_ id: String, _ directory: String?, _ title: String?) async throws -> Session
  public var getSessionChildren: @Sendable (_ id: String, _ directory: String?) async throws -> [Session]
  public var initSession: @Sendable (
    _ id: String, _ directory: String?, _ messageID: String, _ providerID: String, _ modelID: String
  ) async throws -> Bool
  public var abortSession: @Sendable (_ id: String, _ directory: String?) async throws -> Bool
  public var shareSession: @Sendable (_ id: String, _ directory: String?) async throws -> Session
  public var unshareSession: @Sendable (_ id: String, _ directory: String?) async throws -> Session
  public var summarizeSession: @Sendable (
    _ id: String, _ directory: String?, _ providerID: String, _ modelID: String
  ) async throws -> Bool
  public var getSessionMessages: @Sendable (_ id: String, _ directory: String?) async throws -> [MessageWithParts]
  public var sendPrompt: @Sendable (
    _ id: String, _ directory: String?, _ messageID: String?, _ model: ModelConfig?,
    _ agent: String?, _ system: String?, _ tools: [String: Bool]?, _ parts: [PromptPart]
  ) async throws -> AssistantMessageWithParts
  public var getMessage: @Sendable (
    _ id: String, _ messageID: String, _ directory: String?
  ) async throws -> MessageWithParts
  public var sendCommand: @Sendable (
    _ id: String, _ directory: String?, _ messageID: String?, _ agent: String?,
    _ model: String?, _ arguments: String, _ command: String
  ) async throws -> AssistantMessageWithParts
  public var runShellCommand: @Sendable (
    _ id: String, _ directory: String?, _ agent: String, _ command: String
  ) async throws -> AssistantMessage
  public var revertMessage: @Sendable (
    _ id: String, _ directory: String?, _ messageID: String, _ partID: String?
  ) async throws -> Session
  public var unRevertMessages: @Sendable (
    _ id: String, _ directory: String?
  ) async throws -> Session
  public var respondToPermission: @Sendable (
    _ id: String, _ permissionID: String, _ directory: String?, _ response: PermissionResponse
  ) async throws -> Bool
  public var listCommands: @Sendable (_ directory: String?) async throws -> [Command]
  public var listProviders: @Sendable (_ directory: String?) async throws -> ProviderList
  public var findText: @Sendable (_ directory: String?, _ pattern: String) async throws -> [TextMatch]
  public var findFiles: @Sendable (_ directory: String?, _ query: String) async throws -> [String]
  public var findSymbols: @Sendable (_ directory: String?, _ query: String) async throws -> [Symbol]
  public var listFiles: @Sendable (_ directory: String?, _ path: String) async throws -> [FileNode]
  public var readFile: @Sendable (_ directory: String?, _ path: String) async throws -> FileContent
  public var getFileStatus: @Sendable (_ directory: String?) async throws -> [File]
  public var writeLog: @Sendable (
    _ directory: String?, _ service: String, _ level: LogLevel, _ message: String, _ extra: [String: AnyCodable]?
  ) async throws -> Bool
  public var listAgents: @Sendable (_ directory: String?) async throws -> [Agent]
  public var registerTool: @Sendable (_ directory: String?, _ tool: HttpToolRegistration) async throws -> Bool
  public var getToolIDs: @Sendable (_ directory: String?) async throws -> ToolIDs
  public var listTools: @Sendable (_ directory: String?, _ provider: String, _ model: String) async throws -> ToolList
  public var appendPrompt: @Sendable (_ directory: String?, _ text: String) async throws -> Bool
  public var openHelp: @Sendable (_ directory: String?) async throws -> Bool
  public var openSessions: @Sendable (_ directory: String?) async throws -> Bool
  public var openThemes: @Sendable (_ directory: String?) async throws -> Bool
  public var openModels: @Sendable (_ directory: String?) async throws -> Bool
  public var submitPrompt: @Sendable (_ directory: String?) async throws -> Bool
  public var clearPrompt: @Sendable (_ directory: String?) async throws -> Bool
  public var executeTUICommand: @Sendable (_ directory: String?, _ command: String) async throws -> Bool
  public var showToast: @Sendable (
    _ directory: String?, _ title: String?, _ message: String, _ variant: ToastVariant
  ) async throws -> Bool
  public var setAuth: @Sendable (_ id: String, _ directory: String?, _ auth: Auth) async throws -> Bool
  public var subscribeToEvents: @Sendable (_ directory: String?) async throws -> Event
}
