import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import HTTPTypes
import Protocols
import Dependencies
import Models

// MARK: - Message Operations

extension LiveOpenCodeAPIClient {

  public func sendMessage(
    sessionID: String,
    parts: [MessagePart],
    providerID: String?,
    modelID: String?
  ) async throws -> OpenCodeMessage {
    log("OpenCode API: Sending message to session: \(sessionID)")

    let requestBody = createSendMessageRequestBody(
      from: parts,
      providerID: providerID,
      modelID: modelID
    )
    let input = Operations.session_period_prompt.Input(path: .init(id: sessionID), body: requestBody)

    do {
      let response = try await client.session_period_prompt(input)
      return try handleSendMessageResponse(response, sessionID: sessionID)
    } catch {
      log("OpenCode API: Send message failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  private func createSendMessageRequestBody(
    from parts: [MessagePart],
    providerID: String?,
    modelID: String?
  ) -> Operations.session_period_prompt.Input.Body {
    var requestParts: [Operations.session_period_prompt.Input.Body.jsonPayload.partsPayloadPayload] = []

    let textContent = extractTextContent(from: parts)
    if !textContent.isEmpty {
      requestParts.append(createTextPartPayload(textContent))
    }

    requestParts.append(contentsOf: createFilePartPayloads(from: parts))

    let modelPayload = createModelPayload(providerID: providerID, modelID: modelID)

    return Operations.session_period_prompt.Input.Body.json(
      .init(
        model: modelPayload,
        parts: requestParts
      )
    )
  }

  private func extractTextContent(from parts: [MessagePart]) -> String {
    return parts.compactMap { part in
      switch part {
      case let .text(content, _):
        return content
      case let .reasoning(text, _):
        return text
      case let .file(path, content, _):
        return "File: \(path)\n\(content)"
      case let .agent(type, result, _):
        return "Agent: \(type)\n\(result)"
      case let .tool(name, input, output, error, _):
        let errorText = error.map { ", Error: \($0)" } ?? ""
        return "Tool: \(name), Input: \(input), Output: \(output)\(errorText)"
      case let .patch(hash, files, _):
        return "Patch: \(hash), Files: \(files.joined(separator: ", "))"
      case .stepStart:
        return nil
      case let .stepFinish(cost, inputTokens, outputTokens, _):
        return "Step finished - Cost: \(cost), Input tokens: \(inputTokens), Output tokens: \(outputTokens)"
      case let .snapshot(content, _):
        return "Snapshot: \(content)"
      case .structuredFile:
        return nil
      }
    }.joined(separator: "\n")
  }

  private func createTextPartPayload(
    _ text: String
  ) -> Operations.session_period_prompt.Input.Body.jsonPayload.partsPayloadPayload {
    let textPart = Components.Schemas.TextPartInput(
      id: nil, _type: .text, text: text, synthetic: nil, time: nil
    )
    return Operations.session_period_prompt.Input.Body.jsonPayload.partsPayloadPayload(
      value1: textPart, value2: nil, value3: nil
    )
  }

  private func createFilePartPayloads(
    from parts: [MessagePart]
  ) -> [Operations.session_period_prompt.Input.Body.jsonPayload.partsPayloadPayload] {
    return parts.compactMap { part -> Operations.session_period_prompt.Input.Body.jsonPayload.partsPayloadPayload? in
      guard case let .structuredFile(path, url, mimeType, displayText, startIndex, endIndex, id) = part else {
        return nil
      }

      let source = Components.Schemas.FilePartSource(
        value1: Components.Schemas.FileSource(
          text: Components.Schemas.FilePartSourceText(
            value: displayText,
            start: startIndex,
            end: endIndex
          ),
          _type: .file,
          path: path
        ),
        value2: nil
      )

      let filePartInput = Components.Schemas.FilePartInput(
        id: id,
        _type: .file,
        mime: mimeType,
        filename: path,
        url: url,
        source: source
      )

      return Operations.session_period_prompt.Input.Body.jsonPayload.partsPayloadPayload(
        value1: nil, value2: filePartInput, value3: nil
      )
    }
  }

  private func createModelPayload(
    providerID: String?,
    modelID: String?
  ) -> Operations.session_period_prompt.Input.Body.jsonPayload.modelPayload? {
    if let providerID, let modelID {
      return .init(providerID: providerID, modelID: modelID)
    }
    return nil
  }

  private func handleSendMessageResponse(
      _ response: Operations.session_period_prompt.Output,
      sessionID: String
    ) throws -> OpenCodeMessage {
      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case let .json(messageData):
          let message = try parseMessageData(messageData, sessionID: sessionID)
          log("OpenCode API: Successfully sent message to session: \(sessionID)")
          return message
        }
      case let .undocumented(statusCode, _):
        log("OpenCode API: Send message failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to send message: \(statusCode)")
      }
    }

  public func getMessages(sessionID: String) async throws -> [OpenCodeMessage] {
     let startTime = CFAbsoluteTimeGetCurrent()
     log("OpenCode API: Getting messages from session: \(sessionID)", level: .debug)

     let input = Operations.session_period_messages.Input(path: .init(id: sessionID))

     do {
       let response = try await client.session_period_messages(input)

       switch response {
       case let .ok(okResponse):
         switch okResponse.body {
         case let .json(messageList):
           let parseStart = CFAbsoluteTimeGetCurrent()
           let messages = messageList.compactMap { messageData in
             parseMessageData(messageData, sessionID: sessionID)
           }
           let parseTime = CFAbsoluteTimeGetCurrent() - parseStart

           let totalTime = CFAbsoluteTimeGetCurrent() - startTime
           if totalTime > 0.1 {
             let msg = "⚠️ getMessages took \(String(format: "%.3f", totalTime))s"
             let parseMsg = "(parse: \(String(format: "%.3f", parseTime))s)"
             print("\(msg) \(parseMsg) for \(messages.count) messages")
           }

           log(
             "OpenCode API: Successfully retrieved \(messages.count) messages from session: \(sessionID)",
             level: .debug
           )
           return messages
         }
       case let .undocumented(statusCode, _):
         log("OpenCode API: Get messages failed with status code: \(statusCode)", level: .error)
         throw OpenCodeAPIError.serverError("Failed to get messages: \(statusCode)")
       }
     } catch {
       log("OpenCode API: Get messages failed: \(error.localizedDescription)", level: .error)
       throw error
     }
   }

   package enum MessageDataSource {
      case messagesList(Operations.session_period_messages.Output.Ok.Body.jsonPayloadPayload)
      case promptResponse(Operations.session_period_prompt.Output.Ok.Body.jsonPayload)
      case singleMessage(Operations.session_period_message.Output.Ok.Body.jsonPayload)
      case commandResponse(Operations.session_period_command.Output.Ok.Body.jsonPayload)
      case shellResponse(Components.Schemas.AssistantMessage)
    }

   package func parseMessageData(from source: MessageDataSource, sessionID: String) -> OpenCodeMessage? {
      let (messageInfo, parts): (Components.Schemas.Message?, [Components.Schemas.Part])

      switch source {
      case .messagesList(let data):
        messageInfo = data.info
        parts = data.parts
      case .promptResponse(let data):
         messageInfo = Components.Schemas.Message(value1: nil, value2: data.info)
        parts = data.parts
      case .singleMessage(let data):
        messageInfo = data.info
        parts = data.parts
      case .commandResponse(let data):
        messageInfo = Components.Schemas.Message(value1: nil, value2: data.info)
        parts = data.parts
      case .shellResponse(let assistantMessage):
        messageInfo = Components.Schemas.Message(value1: nil, value2: assistantMessage)
        parts = [] // Shell responses might not have parts, or they might be in the message
      }

     guard let info = messageInfo else { return nil }

     let messageInfoResult = extractMessageInfoAndTimestamp(info)
     let messageParts = parseMessageParts(parts)

     return OpenCodeMessage(
       id: messageInfoResult.id,
       sessionID: sessionID,
       parts: messageParts,
       timestamp: messageInfoResult.timestamp,
       role: messageInfoResult.role,
       modelID: messageInfoResult.modelID,
       providerID: messageInfoResult.providerID
     )
   }

  private func parseMessageData(
     _ messageData: Operations.session_period_messages.Output.Ok.Body.jsonPayloadPayload,
     sessionID: String
   ) -> OpenCodeMessage? {
     return parseMessageData(from: .messagesList(messageData), sessionID: sessionID)
   }

   private func parseMessageData(
      _ messageData: Operations.session_period_prompt.Output.Ok.Body.jsonPayload,
      sessionID: String
    ) throws -> OpenCodeMessage {
      guard let message = parseMessageData(from: .promptResponse(messageData), sessionID: sessionID) else {
        throw OpenCodeAPIError.decodingError("Missing message info in prompt response")
      }
      return message
    }

   private func parseMessageData(
      _ messageData: Operations.session_period_message.Output.Ok.Body.jsonPayload,
      sessionID: String
    ) throws -> OpenCodeMessage {
      guard let message = parseMessageData(from: .singleMessage(messageData), sessionID: sessionID) else {
        throw OpenCodeAPIError.decodingError("Missing message info in single message response")
      }
      return message
    }

   private struct MessageInfo {
     let id: String
     let role: MessageRole
     let timestamp: Date
     let modelID: String?
     let providerID: String?
   }

  private func extractMessageInfoAndTimestamp(_ messageInfo: Components.Schemas.Message) -> MessageInfo {
     if let userMessage = messageInfo.value1 {
       let timestamp = Date(timeIntervalSince1970: Double(userMessage.time.created) / 1000)
       return MessageInfo(id: userMessage.id, role: .user, timestamp: timestamp, modelID: nil, providerID: nil)
     } else if let assistantMessage = messageInfo.value2 {
       let timestamp = Date(timeIntervalSince1970: Double(assistantMessage.time.created) / 1000)
       return MessageInfo(
         id: assistantMessage.id,
         role: .assistant,
         timestamp: timestamp,
         modelID: assistantMessage.modelID,
         providerID: assistantMessage.providerID
       )
     } else {
        return MessageInfo(
          id: UUID().uuidString,
          role: .assistant,
          timestamp: Date(),
          modelID: nil,
          providerID: nil
        ) // Fallback
     }
   }

  private func parseMessageParts(_ parts: [Components.Schemas.Part]) -> [MessagePart] {
      parts.compactMap { part in
        if let textPart = part.value1 {
          return .text(textPart.text, id: nil)
        } else if let reasoningPart = part.value2 {
          return .reasoning(reasoningPart.text, id: nil)
        } else if let filePart = part.value3 {
          // Check if this is a structured file part with proper source information
          if let source = filePart.source?.value1 {
            let text = source.text
            return .structuredFile(
              path: source.path,
              url: filePart.url,
              mimeType: filePart.mime,
              displayText: text.value,
              startIndex: Int(text.start),
              endIndex: Int(text.end),
              id: filePart.id
            )
          } else {
            // Fallback to regular file part for backwards compatibility
            return .file(path: filePart.filename ?? "unknown", content: filePart.url, id: nil)
          }
        } else if let toolPart = part.value4 {
          return parseToolPart(toolPart)
        } else if let stepStartPart = part.value5 {
          return .stepStart(id: stepStartPart.id)
        } else if let stepFinishPart = part.value6 {
          return .stepFinish(
            cost: stepFinishPart.cost,
            inputTokens: stepFinishPart.tokens.input,
            outputTokens: stepFinishPart.tokens.output,
            id: stepFinishPart.id
          )
        } else if let snapshotPart = part.value7 {
          return .snapshot(content: snapshotPart.snapshot, id: snapshotPart.id)
        } else if let patchPart = part.value8 {
          return .patch(hash: patchPart.hash, files: patchPart.files, id: nil)
        } else if let agentPart = part.value9 {
          let agentName = agentPart.name
          let content = agentPart.source?.value ?? ""
          return .agent(type: agentName, result: content, id: nil)
        } else {
          log("WARN: Unhandled part type - part may be missing from UI", level: .warning)
          return nil
        }
      }
    }

  private func parseToolPart(_ toolPart: Components.Schemas.ToolPart) -> MessagePart {
      let toolName = toolPart.tool
      var inputString = ""
      var outputString = ""
      var errorString: String?

      if let completed = toolPart.state.value3 {
        inputString = formatToolInput(completed.input.additionalProperties)
        outputString = completed.output
      } else if let running = toolPart.state.value2 {
        inputString = formatToolInputContainer(running.input)
        outputString = ""
      } else if let error = toolPart.state.value4 {
        inputString = formatToolInput(error.input.additionalProperties)
        outputString = ""
        errorString = error.error
      }

      return .tool(name: toolName, input: inputString, output: outputString, error: errorString, id: nil)
    }

  private func formatToolInput(_ input: [String: OpenAPIRuntime.OpenAPIValueContainer]) -> String {
      guard !input.isEmpty else { return "" }

      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(input)
        return String(data: data, encoding: .utf8) ?? ""
      } catch {
        return input.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
      }
    }

  private func formatToolInputContainer(_ input: OpenAPIRuntime.OpenAPIValueContainer) -> String {
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(input)
        return String(data: data, encoding: .utf8) ?? ""
      } catch {
        return "\(input)"
      }
    }

  public func getMessage(sessionID: String, messageID: String) async throws -> OpenCodeMessage {
    let input = Operations.session_period_message.Input(
      path: .init(id: sessionID, messageID: messageID)
    )
    let response = try await client.session_period_message(input)

    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(messageData):
        return try parseMessageData(messageData, sessionID: sessionID)
      }
    case .undocumented:
      throw OpenCodeAPIError.messageNotFound(messageID)
    }
  }

}
