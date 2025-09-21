import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import HTTPTypes
import DependencyClients
import Dependencies
import Models

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
       case let .json(messageData):
         let message = parseMessageData(messageData, sessionID: sessionID)
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
           let messages = messageList.compactMap { messageData in
             parseMessageData(messageData, sessionID: sessionID)
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

   private func parseMessageData(
     _ messageData: Operations.session_period_messages.Output.Ok.Body.jsonPayloadPayload,
     sessionID: String
   ) -> OpenCodeMessage? {
     let messageInfo = messageData.info
     let parts = messageData.parts

     // Extract message ID, role, and timestamp from the message info
     let messageInfoResult = extractMessageInfoAndTimestamp(messageInfo)
     let messageId = messageInfoResult.id
     let role = messageInfoResult.role
     let timestamp = messageInfoResult.timestamp

      // Convert parts to MessagePart array
      let messageParts = parseMessageParts(parts)

      return OpenCodeMessage(
        id: messageId,
        sessionID: sessionID,
        parts: messageParts,
        timestamp: timestamp,
        role: role
      )
    }

   private func parseMessageData(
     _ messageData: Operations.session_period_prompt.Output.Ok.Body.jsonPayload,
     sessionID: String
   ) -> OpenCodeMessage {
     let assistantMessage = messageData.info
     let parts = messageData.parts

     // Extract message ID, role, and timestamp from the assistant message
     let messageId = assistantMessage.id
     let role: MessageRole = .assistant
     let timestamp = Date(timeIntervalSince1970: Double(assistantMessage.time.created) / 1000)

     // Convert parts to MessagePart array
     let messageParts = parseMessageParts(parts)

     return OpenCodeMessage(
       id: messageId,
       sessionID: sessionID,
       parts: messageParts,
       timestamp: timestamp,
       role: role
     )
   }

    private func parseMessageData(
      _ messageData: Operations.session_period_message.Output.Ok.Body.jsonPayload,
      sessionID: String
    ) -> OpenCodeMessage {
      let messageInfo = messageData.info
      let parts = messageData.parts

     // Extract message ID, role, and timestamp from the message info
     let messageInfoResult = extractMessageInfoAndTimestamp(messageInfo)
     let messageId = messageInfoResult.id
     let role = messageInfoResult.role
     let timestamp = messageInfoResult.timestamp

      // Convert parts to MessagePart array
      let messageParts = parseMessageParts(parts)

      return OpenCodeMessage(
        id: messageId,
        sessionID: sessionID,
        parts: messageParts,
        timestamp: timestamp,
        role: role
      )
    }

   private struct MessageInfo {
     let id: String
     let role: MessageRole
     let timestamp: Date
   }

   private func extractMessageInfoAndTimestamp(_ messageInfo: Components.Schemas.Message) -> MessageInfo {
     if let userMessage = messageInfo.value1 {
       let timestamp = Date(timeIntervalSince1970: Double(userMessage.time.created) / 1000)
       return MessageInfo(id: userMessage.id, role: .user, timestamp: timestamp)
     } else if let assistantMessage = messageInfo.value2 {
       let timestamp = Date(timeIntervalSince1970: Double(assistantMessage.time.created) / 1000)
       return MessageInfo(id: assistantMessage.id, role: .assistant, timestamp: timestamp)
     } else {
       return MessageInfo(id: UUID().uuidString, role: .assistant, timestamp: Date()) // Fallback
     }
   }

   private func parseMessageParts(_ parts: [Components.Schemas.Part]) -> [MessagePart] {
     parts.compactMap { part in
       if let textPart = part.value1 {
         return .text(textPart.text)
       } else if let reasoningPart = part.value2 {
         return .text(reasoningPart.text)
       } else if let filePart = part.value3 {
         return .file(path: filePart.filename ?? "unknown", content: filePart.url)
       } else {
         return nil
       }
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
      case let .json(messageData):
        return parseMessageData(messageData, sessionID: sessionID)
      }
    case .undocumented:
      throw OpenCodeAPIError.messageNotFound(messageID)
    }
  }

}
