import Foundation
import Protocols
import Models

extension LiveOpenCodeAPIClient {
  private struct ToolStateInfo {
    let input: String?
    let output: String?
    let error: String?
  }

  package func emitEvent(
    from eventJSON: String,
    continuation: AsyncThrowingStream<OpenCodeEvent, Error>.Continuation
  ) {
    if let event = parseEvent(from: eventJSON) {
      continuation.yield(event)
    }
  }

  package func parseEvent(from jsonString: String) -> OpenCodeEvent? {
    guard let jsonData = jsonString.data(using: .utf8) else {
      log("OpenCode API: Failed to convert event string to UTF-8 data", level: .warning)
      return .unknown(jsonString)
    }

    let json: [String: Any]
    do {
      let parsedObject = try JSONSerialization.jsonObject(
        with: jsonData,
        options: [.allowFragments]
      )
      guard let parsedJSON = parsedObject as? [String: Any] else {
        log(
          "OpenCode API: Event JSON is not a dictionary (type: \(type(of: parsedObject)))",
          level: .warning
        )
        return .unknown(jsonString)
      }
      json = parsedJSON
    } catch {
      let start = jsonString.prefix(50)
      let end = jsonString.suffix(30)
      let preview = jsonString.count > 80 ? "\(start)...\(end)" : jsonString
      log(
        "OpenCode API: Failed to parse event JSON - \(error.localizedDescription). Preview: \(preview)",
        level: .warning
      )
      return .unknown(jsonString)
    }

    guard let type = json["type"] as? String else {
      log("OpenCode API: Event missing 'type' field", level: .warning)
      return .unknown(jsonString)
    }

    switch type {
    case "session.updated":
      return parseSessionUpdatedEvent(json)
    case "session.deleted":
      return parseSessionDeletedEvent(json)
    case "message.updated":
      return parseMessageUpdatedEvent(json)
    case "message.part.updated":
      return parseMessagePartUpdatedEvent(json)
    case "server.connected":
      return nil
    default:
      log("OpenCode API: Received unknown event type: \(type)", level: .debug)
      return .unknown(jsonString)
    }
  }

  package func parseSessionUpdatedEvent(_ json: [String: Any]) -> OpenCodeEvent? {
    guard let sessionData = sessionInfo(from: json),
          let timeData = sessionData["time"] as? [String: Any],
          let created = timeData["created"] as? Double,
          let updated = timeData["updated"] as? Double,
          let id = sessionData["id"] as? String,
          !id.isEmpty else {
      log("OpenCode API: session.updated event missing required fields", level: .warning)
      return nil
    }

    let rawTitle = sessionData["title"] as? String
    let title = rawTitle?.isEmpty == false ? rawTitle : nil
    let session = OpenCodeSession(
      id: id,
      createdAt: Date(timeIntervalSince1970: created),
      updatedAt: Date(timeIntervalSince1970: updated),
      isActive: true,
      title: title
    )
    log("OpenCode API: Received session.updated event for session: \(session.id)")
    return .sessionUpdated(session)
  }

  package func parseSessionDeletedEvent(_ json: [String: Any]) -> OpenCodeEvent? {
    if let sessionData = sessionInfo(from: json),
       let sessionID = sessionData["id"] as? String,
       !sessionID.isEmpty {
      log("OpenCode API: Received session.deleted event for session: \(sessionID)")
      return .sessionDeleted(sessionID)
    }

    if let sessionID = json["data"] as? String, !sessionID.isEmpty {
      log("OpenCode API: Received legacy session.deleted event for session: \(sessionID)")
      return .sessionDeleted(sessionID)
    }

    log("OpenCode API: session.deleted event missing session identifier", level: .warning)
    return nil
  }

  package func parseMessageUpdatedEvent(_ json: [String: Any]) -> OpenCodeEvent? {
    guard let properties = json["properties"] as? [String: Any],
          let messageJSON = properties["info"] as? [String: Any] else {
      log("OpenCode API: message.updated event missing properties.info", level: .warning)
      return nil
    }

    guard let id = messageJSON["id"] as? String,
          let sessionID = messageJSON["sessionID"] as? String else {
      log(
        "OpenCode API: message.updated event missing required fields (id/sessionID)",
        level: .warning
      )
      return nil
    }

    let roleString = messageJSON["role"] as? String ?? MessageRole.assistant.rawValue
    let role = MessageRole(rawValue: roleString) ?? .assistant
    let timestamp = extractTimestamp(from: messageJSON)
    let parts = extractParts(from: properties, messageJSON: messageJSON)
    let modelID = (messageJSON["modelID"] as? String) ?? (messageJSON["modelId"] as? String)
    let providerID = (messageJSON["providerID"] as? String) ?? (messageJSON["providerId"] as? String)

    let message = OpenCodeMessage(
      id: id,
      sessionID: sessionID,
      parts: parts,
      timestamp: timestamp,
      role: role,
      modelID: modelID,
      providerID: providerID
    )
    return .messageUpdated(message)
  }

  package func extractTimestamp(from messageJSON: [String: Any]) -> Date {
    if let timeInfo = messageJSON["time"] as? [String: Any],
       let created = timeInfo["created"] as? Double {
      return Date(timeIntervalSince1970: created / 1000.0)
    }

    if let timestampValue = messageJSON["timestamp"] as? Double {
      return Date(timeIntervalSince1970: timestampValue / 1000.0)
    }

    if let createdAt = messageJSON["createdAt"] as? Double {
      return Date(timeIntervalSince1970: createdAt / 1000.0)
    }

    return Date()
  }

  package func extractParts(from properties: [String: Any], messageJSON: [String: Any]) -> [MessagePart] {
    let partsSource = (properties["parts"] as? [[String: Any]])
      ?? (messageJSON["parts"] as? [[String: Any]])
      ?? []
    return partsSource.compactMap { parseMessagePart($0) }
  }

  package func parseMessagePartUpdatedEvent(_ json: [String: Any]) -> OpenCodeEvent? {
    guard let partJSON = messagePartPayload(from: json) else {
      return nil
    }

    let sessionID = partJSON["sessionID"] as? String
      ?? (json["data"] as? [String: Any])?["sessionID"] as? String
      ?? ""
    let messageID = partJSON["messageID"] as? String
      ?? (json["data"] as? [String: Any])?["messageID"] as? String
      ?? ""

    guard !sessionID.isEmpty, !messageID.isEmpty else {
      log("OpenCode API: message.part.updated missing session or message identifier", level: .warning)
      return nil
    }

    let id = partJSON["id"] as? String ?? UUID().uuidString
    let part = parseMessagePart(partJSON) ?? parseMessagePartFromJSON(partJSON)

    return .messagePartUpdated(sessionID: sessionID, messageID: messageID, partID: id, part: part)
  }

  package func parseMessagePart(_ partJSON: [String: Any]) -> MessagePart? {
    guard let type = partJSON["type"] as? String else { return nil }

    let partCreators: [String: ([String: Any]) -> MessagePart] = [
      "text": createTextPart,
      "reasoning": createReasoningPart,
      "file": createFilePart,
      "tool": createToolPart,
      "agent": createAgentPart,
      "patch": createPatchPart,
      "step-start": createStepStartPart,
      "step-finish": createStepFinishPart,
      "snapshot": createSnapshotPart
    ]

    if let creator = partCreators[type] {
      return creator(partJSON)
    }

    log("OpenCode API: Unknown message part type encountered: \(type)", level: .warning)
    return nil
  }

  package func parseMessagePartFromJSON(_ partJSON: [String: Any]) -> MessagePart {
    let type = partJSON["type"] as? String ?? "text"
    let content = extractString(from: partJSON, keys: ["content", "text"]) ?? ""
    let id = partJSON["id"] as? String ?? UUID().uuidString

    switch type {
    case "reasoning":
      return .reasoning(content, id: id)
    default:
      return .text(content, id: id)
    }
  }

  package func sessionInfo(from json: [String: Any]) -> [String: Any]? {
    if let properties = json["properties"] as? [String: Any],
       let info = properties["info"] as? [String: Any] {
      return info
    }

    if let data = json["data"] as? [String: Any] {
      return data
    }

    return nil
  }

  package func messagePartPayload(from json: [String: Any]) -> [String: Any]? {
    if let properties = json["properties"] as? [String: Any],
       let part = properties["part"] as? [String: Any] {
      return part
    }

    if let data = json["data"] as? [String: Any],
       let part = data["part"] as? [String: Any] {
      return part
    }

    return nil
  }

  package func createTextPart(_ partJSON: [String: Any]) -> MessagePart {
    let text = extractString(from: partJSON, keys: ["content", "text"]) ?? ""
    return .text(text, id: partJSON["id"] as? String)
  }

  package func createReasoningPart(_ partJSON: [String: Any]) -> MessagePart {
    let text = extractString(from: partJSON, keys: ["content", "text"]) ?? ""
    return .reasoning(text, id: partJSON["id"] as? String)
  }

  package func createFilePart(_ partJSON: [String: Any]) -> MessagePart {
    let source = partJSON["source"]
    let path = extractString(from: partJSON, keys: ["path", "url", "filename"])
      ?? extractStringDeep(source, keys: ["path"])
      ?? ""
    let content = extractString(from: partJSON, keys: ["content", "text"])
      ?? extractStringDeep(source, keys: ["value", "text"])
      ?? ""
    return .file(path: path, content: content, id: partJSON["id"] as? String)
  }

  package func createToolPart(_ partJSON: [String: Any]) -> MessagePart {
    let stateInfo = parseToolStateInfo(from: partJSON["state"])
    let input = extractString(from: partJSON, keys: ["input"]) ?? stateInfo.input ?? ""
    let output = extractString(from: partJSON, keys: ["output"]) ?? stateInfo.output ?? ""
    let error = extractString(from: partJSON, keys: ["error"]) ?? stateInfo.error
    let name = extractString(from: partJSON, keys: ["name", "tool"]) ?? ""

    return .tool(
      name: name,
      input: input,
      output: output,
      error: error,
      id: partJSON["id"] as? String
    )
  }

  package func createAgentPart(_ partJSON: [String: Any]) -> MessagePart {
    let type = extractString(from: partJSON, keys: ["name", "type"]) ?? ""
    let result = extractString(from: partJSON, keys: ["result"])
      ?? extractStringDeep(partJSON["source"], keys: ["value"])
      ?? ""
    return .agent(type: type, result: result, id: partJSON["id"] as? String)
  }

  package func createPatchPart(_ partJSON: [String: Any]) -> MessagePart {
    return .patch(
      hash: partJSON["hash"] as? String ?? "",
      files: partJSON["files"] as? [String] ?? [],
      id: partJSON["id"] as? String
    )
  }

  package func createStepStartPart(_ partJSON: [String: Any]) -> MessagePart {
    return .stepStart(id: partJSON["id"] as? String)
  }

  package func createStepFinishPart(_ partJSON: [String: Any]) -> MessagePart {
    let tokens = partJSON["tokens"] as? [String: Any]
    return .stepFinish(
      cost: partJSON["cost"] as? Double ?? 0,
      inputTokens: extractDouble(from: tokens, key: "input")
        ?? partJSON["inputTokens"] as? Double ?? 0,
      outputTokens: extractDouble(from: tokens, key: "output")
        ?? partJSON["outputTokens"] as? Double ?? 0,
      id: partJSON["id"] as? String
    )
  }

  package func createSnapshotPart(_ partJSON: [String: Any]) -> MessagePart {
    let content = extractString(from: partJSON, keys: ["snapshot", "content"]) ?? ""
    return .snapshot(content: content, id: partJSON["id"] as? String)
  }

  package func extractString(from dict: [String: Any], keys: [String]) -> String? {
    for key in keys {
      if let value = dict[key] as? String, !value.isEmpty {
        return value
      }
    }
    return nil
  }

  package func extractStringDeep(_ value: Any?, keys: [String]) -> String? {
    guard let value else { return nil }

    if let dict = value as? [String: Any] {
      if let direct = extractString(from: dict, keys: keys) {
        return direct
      }
      for nested in dict.values {
        if let result = extractStringDeep(nested, keys: keys) {
          return result
        }
      }
    } else if let array = value as? [Any] {
      for element in array {
        if let result = extractStringDeep(element, keys: keys) {
          return result
        }
      }
    }

    return nil
  }

  package func extractDouble(from dict: [String: Any]?, key: String) -> Double? {
    guard let dict else { return nil }

    if let value = dict[key] as? Double {
      return value
    }

    if let value = dict[key] as? NSNumber {
      return value.doubleValue
    }

    if let value = dict[key] as? String, let doubleValue = Double(value) {
      return doubleValue
    }

    return nil
  }

  package func stringifyJSON(_ value: Any?) -> String? {
    guard let value else { return nil }

    if let string = value as? String, !string.isEmpty {
      return string
    }

    if let number = value as? NSNumber {
      return number.stringValue
    }

    if let bool = value as? Bool {
      return bool ? "true" : "false"
    }

    if value is NSNull {
      return "null"
    }

    if let array = value as? [Any], JSONSerialization.isValidJSONObject(array),
       let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
       let string = String(data: data, encoding: .utf8) {
      return string
    }

    if let dict = value as? [String: Any], JSONSerialization.isValidJSONObject(dict),
       let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
       let string = String(data: data, encoding: .utf8) {
      return string
    }

    return nil
  }

  private func parseToolStateInfo(from stateValue: Any?) -> ToolStateInfo {
    guard let state = stateValue as? [String: Any] else {
      return ToolStateInfo(input: nil, output: nil, error: nil)
    }

    let input = stringifyJSON(state["input"])
      ?? extractStringDeep(state["input"], keys: ["value"])
    let output = extractString(from: state, keys: ["output"])
      ?? stringifyJSON(state["output"])
    let error = extractString(from: state, keys: ["error"])
      ?? stringifyJSON(state["error"])

    return ToolStateInfo(input: input, output: output, error: error)
  }
}
