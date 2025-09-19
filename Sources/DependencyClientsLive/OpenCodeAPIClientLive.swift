// swiftlint:disable file_length

import DependencyClients
import Foundation
import OpenAPIAsyncHTTPClient
import OpenAPIGenerated
import OpenAPIRuntime
import ComposableArchitecture

// swiftlint:disable:next type_body_length
public struct OpenCodeAPIClientLive: @unchecked Sendable {
  private let client: Client
  private let serverURL: URL
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()

  public init(serverURL: URL) {
    self.serverURL = serverURL
    self.client = Client(
      serverURL: serverURL,
      transport: AsyncHTTPClientTransport()
    )
  }

  public func listProjects(directory: String? = nil) async throws -> [Project] {
    let response = try await client.project_period_list(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let projects):
        return try decodeGenerated(projects, as: [Project].self)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func getCurrentProject(directory: String? = nil) async throws -> Project {
    let response = try await client.project_period_current(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let project):
        return try decodeGenerated(project, as: Project.self)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  // swiftlint:disable function_body_length
  public func getConfig(directory: String? = nil) async throws -> Config {
    let response = try await client.config_period_get(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let config):
        return try decodeGenerated(config, as: Config.self)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }
  // swiftlint:enable function_body_length

  public func getPath(directory: String? = nil) async throws -> Path {
    let response = try await client.path_period_get(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let path):
        return Path(path: path.path)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func listSessions(directory: String? = nil) async throws -> [Session] {
    let response = try await client.session_period_list(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let sessions):
        return sessions.map {
          Session(
            id: $0.id,
            title: $0.title,
            parentID: $0.parent_id,
            created: $0.created,
            updated: $0.updated,
            share: $0.share
          )
        }
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func createSession(
    directory: String? = nil, parentID: String? = nil, title: String? = nil
  ) async throws -> Session {
    let body = Operations.session_period_create.Input.Body.json(
      .init(parent_id: parentID, title: title)
    )
    let response = try await client.session_period_create(query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let session):
        return Session(
          id: session.id,
          title: session.title,
          parentID: session.parent_id,
          created: session.created,
          updated: session.updated,
          share: session.share
        )
      }
    case .badRequest(let badRequestResponse):
      switch badRequestResponse.body {
      case .json(let error):
        throw OpenCodeAPIError.apiError(message: error.error)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func getSession(id: String, directory: String? = nil) async throws -> Session {
    let response = try await client.session_period_get(
      path: .init(id: id), query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let session):
        return Session(
          id: session.id,
          title: session.title,
          parentID: session.parent_id,
          created: session.created,
          updated: session.updated,
          share: session.share
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func deleteSession(id: String, directory: String? = nil) async throws -> Bool {
    let response = try await client.session_period_delete(
      path: .init(id: id), query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func updateSession(id: String, directory: String? = nil, title: String? = nil) async throws
    -> Session {
    let body = Operations.session_period_update.Input.Body.json(.init(title: title))
    let response = try await client.session_period_update(
      path: .init(id: id), query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let session):
        return Session(
          id: session.id,
          title: session.title,
          parentID: session.parent_id,
          created: session.created,
          updated: session.updated,
          share: session.share
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func getSessionChildren(id: String, directory: String? = nil) async throws -> [Session] {
    let response = try await client.session_period_children(
      path: .init(id: id), query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let sessions):
        return sessions.map {
          Session(
            id: $0.id,
            title: $0.title,
            parentID: $0.parent_id,
            created: $0.created,
            updated: $0.updated,
            share: $0.share
          )
        }
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func initSession(
    id: String, directory: String? = nil, messageID: String, providerID: String, modelID: String
  ) async throws -> Bool {
    let body = Operations.session_period_init.Input.Body.json(
      .init(message_id: messageID, provider_id: providerID, model_id: modelID))
    let response = try await client.session_period_init(
      path: .init(id: id), query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func abortSession(id: String, directory: String? = nil) async throws -> Bool {
    let response = try await client.session_period_abort(
      path: .init(id: id), query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func shareSession(id: String, directory: String? = nil) async throws -> Session {
    let response = try await client.session_period_share(
      path: .init(id: id), query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let session):
        return Session(
          id: session.id,
          title: session.title,
          parentID: session.parent_id,
          created: session.created,
          updated: session.updated,
          share: session.share
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func unshareSession(id: String, directory: String? = nil) async throws -> Session {
    let response = try await client.session_period_unshare(
      path: .init(id: id), query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let session):
        return Session(
          id: session.id,
          title: session.title,
          parentID: session.parent_id,
          created: session.created,
          updated: session.updated,
          share: session.share
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func summarizeSession(
    id: String, directory: String? = nil, providerID: String, modelID: String
  ) async throws -> Bool {
    let body = Operations.session_period_summarize.Input.Body.json(
      .init(provider_id: providerID, model_id: modelID))
    let response = try await client.session_period_summarize(
      path: .init(id: id), query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func getSessionMessages(id: String, directory: String? = nil) async throws
    -> [MessageWithParts] {
    let response = try await client.session_period_messages(
      path: .init(id: id), query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let messages):
        return messages.map { message in
          MessageWithParts(
            info: Message(
              id: message.info.id,
              role: message.info.role,
              created: message.info.created,
              providerID: message.info.provider_id,
              modelID: message.info.model_id
            ),
            parts: message.parts.compactMap { convertGeneratedPart($0) }
          )
        }
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func sendPrompt(
    id: String, directory: String? = nil, messageID: String? = nil, model: ModelConfig? = nil,
    agent: String? = nil, system: String? = nil, tools: [String: Bool]? = nil, parts: [PromptPart]
  ) async throws -> AssistantMessageWithParts {
    let body = Operations.session_period_prompt.Input.Body.json(
      .init(
        message_id: messageID,
        model: model.map { .init(provider_id: $0.providerID, model_id: $0.modelID) },
        agent: agent,
        system: system,
        tools: tools,
        parts: parts.map { convertPromptPartToGenerated($0) }
      ))
    let response = try await client.session_period_prompt(
      path: .init(id: id), query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let message):
        return AssistantMessageWithParts(
          info: AssistantMessage(
            id: message.info.id,
            role: message.info.role,
            created: message.info.created,
            providerID: message.info.provider_id,
            modelID: message.info.model_id
          ),
          parts: message.parts.compactMap { convertGeneratedPart($0) }
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func getMessage(id: String, messageID: String, directory: String? = nil) async throws
    -> MessageWithParts {
    let response = try await client.session_period_message(
      path: .init(id: id, message_id: messageID), query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let message):
        return MessageWithParts(
          info: Message(
            id: message.info.id,
            role: message.info.role,
            created: message.info.created,
            providerID: message.info.provider_id,
            modelID: message.info.model_id
          ),
          parts: message.parts.compactMap { convertGeneratedPart($0) }
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func sendCommand(
    id: String, directory: String? = nil, messageID: String? = nil, agent: String? = nil,
    model: String? = nil, arguments: String, command: String
  ) async throws -> AssistantMessageWithParts {
    let body = Operations.session_period_command.Input.Body.json(
      .init(
        message_id: messageID,
        agent: agent,
        model: model,
        arguments: arguments,
        command: command
      ))
    let response = try await client.session_period_command(
      path: .init(id: id), query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let message):
        return AssistantMessageWithParts(
          info: AssistantMessage(
            id: message.info.id,
            role: message.info.role,
            created: message.info.created,
            providerID: message.info.provider_id,
            modelID: message.info.model_id
          ),
          parts: message.parts.compactMap { convertGeneratedPart($0) }
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func runShellCommand(id: String, directory: String? = nil, agent: String, command: String)
    async throws -> AssistantMessage {
    let body = Operations.session_period_shell.Input.Body.json(.init(agent: agent, command: command))
    let response = try await client.session_period_shell(
      path: .init(id: id), query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let message):
        return AssistantMessage(
          id: message.id,
          role: message.role,
          created: message.created,
          providerID: message.provider_id,
          modelID: message.model_id
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func revertMessage(
    id: String, directory: String? = nil, messageID: String, partID: String? = nil
  ) async throws -> Session {
    let body = Operations.session_period_revert.Input.Body.json(
      .init(message_id: messageID, part_id: partID))
    let response = try await client.session_period_revert(
      path: .init(id: id), query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let session):
        return Session(
          id: session.id,
          title: session.title,
          parentID: session.parent_id,
          created: session.created,
          updated: session.updated,
          share: session.share
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func unRevertMessages(id: String, directory: String? = nil) async throws -> Session {
    let response = try await client.session_period_unrevert(
      path: .init(id: id), query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let session):
        return Session(
          id: session.id,
          title: session.title,
          parentID: session.parent_id,
          created: session.created,
          updated: session.updated,
          share: session.share
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func respondToPermission(
    id: String, permissionID: String, directory: String? = nil, response: PermissionResponse
  ) async throws -> Bool {
    let body = Operations.postSession_colon_idPermissions_colon_permissionID.Input.Body.json(
      .init(response: response.rawValue))
    let apiResponse = try await client.postSession_colon_idPermissions_colon_permissionID(
      path: .init(id: id, permission_id: permissionID),
      query: .init(directory: directory),
      body: body
    )
    switch apiResponse {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .badRequest(let badRequestResponse):
      switch badRequestResponse.body {
      case .json(let error):
        throw OpenCodeAPIError.apiError(message: error.error)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func listCommands(directory: String? = nil) async throws -> [Command] {
    let response = try await client.command_period_list(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let commands):
        return commands.map { Command(id: $0.id, name: $0.name, description: $0.description) }
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func listProviders(directory: String? = nil) async throws -> ProviderList {
    let response = try await client.config_period_providers(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let providerList):
        return ProviderList(
          providers: providerList.providers.map {
            Provider(
              id: $0.id,
              name: $0.name,
              models: $0.models.map { Model(id: $0.id, name: $0.name) }
            )
          },
          default: providerList.default
        )
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func findText(directory: String? = nil, pattern: String) async throws -> [TextMatch] {
    let response = try await client.find_period_text(query: .init(directory: directory, pattern: pattern))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let matches):
        return matches.map { match in
          TextMatch(
            path: TextMatchPath(text: match.path.text),
            lines: TextMatchLines(text: match.lines.text),
            lineNumber: match.line_number,
            absoluteOffset: match.absolute_offset,
            submatches: match.submatches.map { submatch in
              TextMatchSubmatch(
                match: TextMatchInfo(text: submatch.match.text),
                start: submatch.start,
                end: submatch.end
              )
            }
          )
        }
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func findFiles(directory: String? = nil, query: String) async throws -> [String] {
    let response = try await client.find_period_files(query: .init(directory: directory, query: query))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let files):
        return files
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func findSymbols(directory: String? = nil, query: String) async throws -> [Symbol] {
    let response = try await client.find_period_symbols(query: .init(directory: directory, query: query))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let symbols):
        return symbols.map { Symbol(name: $0.name, kind: $0.kind, container: $0.container) }
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func listFiles(directory: String? = nil, path: String) async throws -> [FileNode] {
    let response = try await client.file_period_list(query: .init(directory: directory, path: path))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let files):
        return files.map {
          FileNode(path: $0.path, name: $0.name, type: FileNodeType(rawValue: $0.type) ?? .file)
        }
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func readFile(directory: String? = nil, path: String) async throws -> FileContent {
    let response = try await client.file_period_read(query: .init(directory: directory, path: path))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let fileContent):
        return FileContent(
          path: fileContent.path, content: fileContent.content, language: fileContent.language)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func getFileStatus(directory: String? = nil) async throws -> [File] {
    let response = try await client.file_period_status(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let files):
        return files.map { File(path: $0.path, status: $0.status) }
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func writeLog(
    directory: String? = nil, service: String, level: LogLevel, message: String,
    extra: [String: AnyCodable]? = nil
  ) async throws -> Bool {
    let body = Operations.app_period_log.Input.Body.json(
      .init(
        service: service,
        level: level.rawValue,
        message: message,
        extra: extra
      ))
    let response = try await client.app_period_log(query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func listAgents(directory: String? = nil) async throws -> [Agent] {
    let response = try await client.app_period_agents(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let agents):
        return agents.map { Agent(id: $0.id, name: $0.name, description: $0.description) }
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func registerTool(directory: String? = nil, tool: HttpToolRegistration) async throws
    -> Bool {
    let body = Operations.tool_register.Input.Body.json(
      .init(
        name: tool.name,
        description: tool.description,
        input_schema: tool.inputSchema,
        url: tool.url,
        headers: tool.headers
      ))
    let response = try await client.tool_register(query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .badRequest(let badRequestResponse):
      switch badRequestResponse.body {
      case .json(let error):
        throw OpenCodeAPIError.apiError(message: error.error)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func getToolIDs(directory: String? = nil) async throws -> ToolIDs {
    let response = try await client.tool_period_ids(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let toolIDs):
        return ToolIDs(toolIDs: toolIDs.tool_ids)
      }
    case .badRequest(let badRequestResponse):
      switch badRequestResponse.body {
      case .json(let error):
        throw OpenCodeAPIError.apiError(message: error.error)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func listTools(directory: String? = nil, provider: String, model: String) async throws
    -> ToolList {
    let response = try await client.tool_period_list(
      query: .init(directory: directory, provider: provider, model: model))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let toolList):
        return ToolList(
          tools: toolList.tools.map {
            Tool(
              name: $0.name,
              description: $0.description,
              inputSchema: $0.input_schema
            )
          })
      }
    case .badRequest(let badRequestResponse):
      switch badRequestResponse.body {
      case .json(let error):
        throw OpenCodeAPIError.apiError(message: error.error)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func appendPrompt(directory: String? = nil, text: String) async throws -> Bool {
    let body = Operations.tui_period_appendPrompt.Input.Body.json(.init(text: text))
    let response = try await client.tui_period_appendPrompt(query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func openHelp(directory: String? = nil) async throws -> Bool {
    let response = try await client.tui_period_openHelp(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func openSessions(directory: String? = nil) async throws -> Bool {
    let response = try await client.tui_period_openSessions(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func openThemes(directory: String? = nil) async throws -> Bool {
    let response = try await client.tui_period_openThemes(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func openModels(directory: String? = nil) async throws -> Bool {
    let response = try await client.tui_period_openModels(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func submitPrompt(directory: String? = nil) async throws -> Bool {
    let response = try await client.tui_period_submitPrompt(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func clearPrompt(directory: String? = nil) async throws -> Bool {
    let response = try await client.tui_period_clearPrompt(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func executeTUICommand(directory: String? = nil, command: String) async throws -> Bool {
    let body = Operations.tui_period_executeCommand.Input.Body.json(.init(command: command))
    let response = try await client.tui_period_executeCommand(
      query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func showToast(
    directory: String? = nil, title: String? = nil, message: String, variant: ToastVariant
  ) async throws -> Bool {
    let body = Operations.tui_period_showToast.Input.Body.json(
      .init(
        title: title,
        message: message,
        variant: variant.rawValue
      ))
    let response = try await client.tui_period_showToast(query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func setAuth(id: String, directory: String? = nil, auth: Auth) async throws -> Bool {
    let body = Operations.auth_period_set.Input.Body.json(.init(provider: auth.provider, data: auth.data))
    let response = try await client.auth_period_set(
      path: .init(id: id), query: .init(directory: directory), body: body)
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .json(let success):
        return success
      }
    case .badRequest(let badRequestResponse):
      switch badRequestResponse.body {
      case .json(let error):
        throw OpenCodeAPIError.apiError(message: error.error)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  public func subscribeToEvents(directory: String? = nil) async throws -> Event {
    let response = try await client.event_period_subscribe(query: .init(directory: directory))
    switch response {
    case .ok(let okResponse):
      switch okResponse.body {
      case .text_event_hyphen_stream(let event):
        return Event(event: event.event, data: event.data)
      }
    case .undocumented(let statusCode, _):
      throw OpenCodeAPIError.httpError(statusCode: statusCode)
    }
  }

  // MARK: - Helper Functions

  private func convertGeneratedPart(_ part: Components.Schemas.Part) -> Part? {
    if let text = part.value1 {
      return Part(id: text.id, content: .text(TextPart(text: text.text)))
    }

    if let reasoning = part.value2 {
      return Part(id: reasoning.id, content: .text(TextPart(text: reasoning.text)))
    }

    if let file = part.value3 {
      let sourceText = file.source?.text
      let fileContent = FileContent(
        path: file.url,
        content: sourceText?.value,
        language: file.mime
      )
      return Part(id: file.id, content: .file(FilePart(file: fileContent)))
    }

    if let tool = part.value4 {
      let description = "[Tool] \(tool.tool)"
      return Part(id: tool.id, content: .text(TextPart(text: description)))
    }

    if let stepStart = part.value5 {
      return Part(id: stepStart.id, content: .text(TextPart(text: "[Step Start]")))
    }

    if let stepFinish = part.value6 {
      let description = "[Step Finish] cost: \(stepFinish.cost)"
      return Part(id: stepFinish.id, content: .text(TextPart(text: description)))
    }

    if let snapshot = part.value7 {
      return Part(id: snapshot.id, content: .text(TextPart(text: snapshot.snapshot)))
    }

    if let patch = part.value8 {
      let files = patch.files.joined(separator: ", ")
      let description = files.isEmpty ? "[Patch]" : "[Patch] files: \(files)"
      return Part(id: patch.id, content: .text(TextPart(text: description)))
    }

    if let agent = part.value9 {
      let agentContent = AgentContent(name: agent.name, arguments: agent.source?.value)
      return Part(id: agent.id, content: .agent(AgentPart(agent: agentContent)))
    }

    return nil
  }

  private func convertPromptPartToGenerated(
    _ part: PromptPart
  ) -> Operations.session_period_prompt.Input.Body.jsonPayload.partsPayloadPayload {
    switch part {
    case .text(let textPart):
      let generated = Components.Schemas.TextPartInput(
        id: nil,
        _type: .text,
        text: textPart.text,
        synthetic: nil,
        time: nil
      )
      return .init(value1: generated)

    case .file(let filePart):
      let generated = Components.Schemas.FilePartInput(
        id: nil,
        _type: .file,
        mime: "application/octet-stream",
        filename: nil,
        url: filePart.file,
        source: nil
      )
      return .init(value2: generated)

    case .agent(let agentPart):
      let generated = Components.Schemas.AgentPartInput(
        id: nil,
        _type: .agent,
        name: agentPart.agent,
        source: nil
      )
      return .init(value3: generated)
    }
  }

  private func decodeGenerated<T: Decodable>(_ value: some Encodable, as type: T.Type = T.self) throws -> T {
    let data = try jsonEncoder.encode(value)
    return try jsonDecoder.decode(T.self, from: data)
  }
}

public enum OpenCodeAPIError: LocalizedError {
  case httpError(statusCode: Int)
  case apiError(message: String)
  case networkError(any Swift.Error)

  public var errorDescription: String? {
    switch self {
    case .httpError(let statusCode):
      return "HTTP error: \(statusCode)"
    case .apiError(let message):
      return "API error: \(message)"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    }
  }
}

extension OpenCodeAPIClient: DependencyKey {
  public static let liveValue = createLiveClient()

  // swiftlint:disable function_body_length
  private static func createLiveClient() -> OpenCodeAPIClient {
    // Default server URL - can be configured via dependency injection
    let serverURL = URL(string: "http://localhost:8080")!
    let apiClient = OpenCodeAPIClientLive(serverURL: serverURL)

    return OpenCodeAPIClient(
      listProjects: { try await apiClient.listProjects(directory: $0) },
      getCurrentProject: { try await apiClient.getCurrentProject(directory: $0) },
      getConfig: { try await apiClient.getConfig(directory: $0) },
      getPath: { try await apiClient.getPath(directory: $0) },
      listSessions: { try await apiClient.listSessions(directory: $0) },
      createSession: { try await apiClient.createSession(directory: $0, parentID: $1, title: $2) },
      getSession: { try await apiClient.getSession(id: $0, directory: $1) },
      deleteSession: { try await apiClient.deleteSession(id: $0, directory: $1) },
      updateSession: { try await apiClient.updateSession(id: $0, directory: $1, title: $2) },
      getSessionChildren: { try await apiClient.getSessionChildren(id: $0, directory: $1) },
      initSession: {
        try await apiClient.initSession(
          id: $0, directory: $1, messageID: $2, providerID: $3, modelID: $4)
      },
      abortSession: { try await apiClient.abortSession(id: $0, directory: $1) },
      shareSession: { try await apiClient.shareSession(id: $0, directory: $1) },
      unshareSession: { try await apiClient.unshareSession(id: $0, directory: $1) },
      summarizeSession: {
        try await apiClient.summarizeSession(id: $0, directory: $1, providerID: $2, modelID: $3)
      },
      getSessionMessages: { try await apiClient.getSessionMessages(id: $0, directory: $1) },
      sendPrompt: {
        try await apiClient.sendPrompt(
          id: $0, directory: $1, messageID: $2, model: $3, agent: $4, system: $5, tools: $6,
          parts: $7)
      },
      getMessage: { try await apiClient.getMessage(id: $0, messageID: $1, directory: $2) },
      sendCommand: {
        try await apiClient.sendCommand(
          id: $0, directory: $1, messageID: $2, agent: $3, model: $4, arguments: $5, command: $6)
      },
      runShellCommand: {
        try await apiClient.runShellCommand(id: $0, directory: $1, agent: $2, command: $3)
      },
      revertMessage: {
        try await apiClient.revertMessage(id: $0, directory: $1, messageID: $2, partID: $3)
      },
      unRevertMessages: { try await apiClient.unRevertMessages(id: $0, directory: $1) },
      respondToPermission: {
        try await apiClient.respondToPermission(
          id: $0, permissionID: $1, directory: $2, response: $3)
      },
      listCommands: { try await apiClient.listCommands(directory: $0) },
      listProviders: { try await apiClient.listProviders(directory: $0) },
      findText: { try await apiClient.findText(directory: $0, pattern: $1) },
      findFiles: { try await apiClient.findFiles(directory: $0, query: $1) },
      findSymbols: { try await apiClient.findSymbols(directory: $0, query: $1) },
      listFiles: { try await apiClient.listFiles(directory: $0, path: $1) },
      readFile: { try await apiClient.readFile(directory: $0, path: $1) },
      getFileStatus: { try await apiClient.getFileStatus(directory: $0) },
      writeLog: {
        try await apiClient.writeLog(directory: $0, service: $1, level: $2, message: $3, extra: $4)
      },
      listAgents: { try await apiClient.listAgents(directory: $0) },
      registerTool: { try await apiClient.registerTool(directory: $0, tool: $1) },
      getToolIDs: { try await apiClient.getToolIDs(directory: $0) },
      listTools: { try await apiClient.listTools(directory: $0, provider: $1, model: $2) },
      appendPrompt: { try await apiClient.appendPrompt(directory: $0, text: $1) },
      openHelp: { try await apiClient.openHelp(directory: $0) },
      openSessions: { try await apiClient.openSessions(directory: $0) },
      openThemes: { try await apiClient.openThemes(directory: $0) },
      openModels: { try await apiClient.openModels(directory: $0) },
      submitPrompt: { try await apiClient.submitPrompt(directory: $0) },
      clearPrompt: { try await apiClient.clearPrompt(directory: $0) },
      executeTUICommand: { try await apiClient.executeTUICommand(directory: $0, command: $1) },
      showToast: {
        try await apiClient.showToast(directory: $0, title: $1, message: $2, variant: $3)
      },
      setAuth: { try await apiClient.setAuth(id: $0, directory: $1, auth: $2) },
      subscribeToEvents: { try await apiClient.subscribeToEvents(directory: $0) }
    )
  }
  // swiftlint:enable function_body_length
}
