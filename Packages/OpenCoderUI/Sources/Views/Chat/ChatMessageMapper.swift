import Protocols
import ExyteChat
import Foundation

enum ChatMessageMapper {
  struct BuildResult {
    var messages: [Message]
    var enhancedParts: [String: [EnhancedMessagePart]]
    var identifiedParts: [String: [IdentifiedEnhancedPart]]
    var unsupportedParts: Set<ChatUnsupportedMessagePartKind>
  }

  struct MessageResult {
    let message: Message
    let enhancedParts: [EnhancedMessagePart]
    let identifiedParts: [IdentifiedEnhancedPart]
    let unsupportedParts: Set<ChatUnsupportedMessagePartKind>
  }

  struct ContentResult {
    let text: String
    let enhancedParts: [EnhancedMessagePart]
    let unsupportedParts: Set<ChatUnsupportedMessagePartKind>
  }
  static func buildMessages(
    from messages: [OpenCodeMessage]
  ) -> BuildResult {
    let startTime = CFAbsoluteTimeGetCurrent()

    let result = messages.reduce(into: BuildResult(
      messages: [],
      enhancedParts: [:],
      identifiedParts: [:],
      unsupportedParts: []
    )) { result, message in
      let mapped = map(message: message)
      result.messages.append(mapped.message)
      if !mapped.enhancedParts.isEmpty {
        result.enhancedParts[message.id] = mapped.enhancedParts
      }
      if !mapped.identifiedParts.isEmpty {
        result.identifiedParts[message.id] = mapped.identifiedParts
      }
      result.unsupportedParts.formUnion(mapped.unsupportedParts)
    }

    let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
    if timeElapsed > 0.1 {
      let msg = "⚠️ ChatMessageMapper.buildMessages took \(String(format: "%.3f", timeElapsed))s"
      print("\(msg) for \(messages.count) messages")
    }

    return result
  }

  private static func map(
    message: OpenCodeMessage
  ) -> MessageResult {
    let content = textAndEnhancedParts(from: message.parts)
    let identified = identifiedEnhancedParts(from: message.parts, messageID: message.id)
    let user = user(for: message.role, message: message)
    let status = status(for: message.role)

    // Use fallback text if no text content but have enhanced parts
    let displayText = content.text.isEmpty && !content.enhancedParts.isEmpty
      ? generateFallbackText(from: content.enhancedParts)
      : content.text

    let exyteMessage = Message(
      id: message.id,
      user: user,
      status: status,
      createdAt: message.timestamp,
      text: displayText
    )
    return MessageResult(
      message: exyteMessage,
      enhancedParts: content.enhancedParts,
      identifiedParts: identified,
      unsupportedParts: content.unsupportedParts
    )
  }

  private static func textAndEnhancedParts(
    from parts: [MessagePart]
  ) -> ContentResult {
    var textSegments: [String] = []
    var enhancedParts: [EnhancedMessagePart] = []

    for part in parts {
      let result = processMessagePart(part)
      if let text = result.text {
        textSegments.append(text)
      }
      if let enhanced = result.enhancedPart {
        enhancedParts.append(enhanced)
      }
    }

    return ContentResult(
      text: textSegments.joined(separator: "\n"),
      enhancedParts: enhancedParts,
      unsupportedParts: []
    )
  }

  private static func processMessagePart(_ part: MessagePart) -> (text: String?, enhancedPart: EnhancedMessagePart?) {
    switch part {
    case let .text(content, _):
      return (content, .text(content))
    case let .reasoning(content, _):
      return (nil, .reasoning(content))
    case let .file(path, content, _):
      return (nil, .file(path: path, content: content, operation: .read))
    case let .structuredFile(path, _, _, _, _, _, _):
      // Treat structured file similarly to a read file for rendering purposes.
      return (nil, .file(path: path, content: "", operation: .read))
    case let .agent(agentType, content, _):
      return (nil, .agent(content, agentType: agentType))
    case let .tool(name, input, output, error, _):
      return (nil, createToolEnhancedPart(name: name, input: input, output: output, error: error))
    case .patch:
      return (nil, nil)
    case .stepStart:
      return (nil, nil)
    case let .stepFinish(cost, inputTokens, outputTokens, id):
      let part = createStepFinishEnhancedPart(
        cost: cost,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        id: id
      )
      return (nil, part)
    case let .snapshot(content, id):
      return (nil, .snapshot(content, snapshotID: id ?? ""))
    }
  }

  private static func createToolEnhancedPart(
    name: String,
    input: String,
    output: String,
    error: String?
  ) -> EnhancedMessagePart {
    let state: EnhancedMessagePart.ToolState
    if let error = error, !error.isEmpty {
      state = .error
    } else if output.isEmpty {
      state = .running
    } else {
      state = .completed
    }
    let toolInfo = EnhancedMessagePart.ToolCallInfo(
      id: UUID().uuidString,
      name: name,
      state: state,
      input: input,
      output: output,
      error: error
    )
    return .tool(toolInfo)
  }

  private static func createStepFinishEnhancedPart(
    cost: Double,
    inputTokens: Double,
    outputTokens: Double,
    id: String?
  ) -> EnhancedMessagePart? {
    guard cost != 0 else { return nil }
    let text = "Cost: $\(String(format: "%.4f", cost)), Tokens: \(Int(inputTokens)) in / \(Int(outputTokens)) out"
    return .stepFinish(text, stepID: id ?? "", success: true)
  }
  private static func generateFallbackText(from enhancedParts: [EnhancedMessagePart]) -> String {
    let descriptions = enhancedParts.compactMap { part in
      switch part {
      case .text(let content):
        return content.isEmpty ? nil : content
      case .file(let path, _, _):
        return "📄 \(path)"
      case .tool(let toolInfo):
        return "🔧 \(toolInfo.name)"
      case .agent(_, let agentType):
        return "🤖 \(agentType) agent"
      case .stepFinish(let text, _, _):
        return "✅ \(text)"
      case .snapshot(let text, _):
        return "📸 \(text)"
      case .reasoning:
        return "💭 Reasoning"
      case .stepStart:
        return nil
      case .patch:
        return nil
      }
    }

    return descriptions.isEmpty ? "Message content" : descriptions.joined(separator: "\n")
  }

  private static func user(for role: MessageRole, message: OpenCodeMessage) -> User {
    switch role {
    case .user:
      User(id: "user", name: "You", avatarURL: nil, avatarCacheKey: nil, isCurrentUser: true)
    case .assistant:
      User(id: "assistant", name: message.displayModelName, avatarURL: nil, avatarCacheKey: nil, isCurrentUser: false)
    case .system:
      User(id: "system", name: "System", avatarURL: nil, avatarCacheKey: nil, type: .system)
    }
  }

  private static func status(for role: MessageRole) -> Message.Status? {
    switch role {
    case .user:
      return .sent
    case .assistant:
      return .read
    case .system:
      return nil
    }
  }

  // MARK: - Identified Parts for Stable Rendering

  struct IdentifiedEnhancedPart: Equatable, Identifiable, Sendable {
    let id: String
    let part: EnhancedMessagePart
  }

  private static func identifiedEnhancedParts(
    from parts: [MessagePart],
    messageID: String
  ) -> [IdentifiedEnhancedPart] {
    var result: [IdentifiedEnhancedPart] = []
    for (index, part) in parts.enumerated() {
      let enhanced = processMessagePart(part).enhancedPart
      guard let enhanced else { continue }
      let key = partStableID(part, fallback: makeFallbackID(messageID: messageID, index: index, part: part))
      result.append(IdentifiedEnhancedPart(id: key, part: enhanced))
    }
    return result
  }

  private static func partStableID(_ part: MessagePart, fallback: String) -> String {
    switch part {
    case let .text(_, id):
      return id ?? fallback
    case let .reasoning(_, id):
      return id ?? fallback
    case let .file(_, _, id):
      return id ?? fallback
    case let .structuredFile(_, _, _, _, _, _, id):
      return id ?? fallback
    case let .agent(_, _, id):
      return id ?? fallback
    case let .tool(_, _, _, _, id):
      return id ?? fallback
    case let .patch(_, _, id):
      return id ?? fallback
    case let .stepStart(id):
      return id ?? fallback
    case let .stepFinish(_, _, _, id):
      return id ?? fallback
    case let .snapshot(_, id):
      return id ?? fallback
    }
  }

  private static func makeFallbackID(messageID: String, index: Int, part: MessagePart) -> String {
    let kind: String
    switch part {
    case .text: kind = "text"
    case .reasoning: kind = "reasoning"
    case .file: kind = "file"
    case .structuredFile: kind = "structuredFile"
    case .agent: kind = "agent"
    case .tool: kind = "tool"
    case .patch: kind = "patch"
    case .stepStart: kind = "stepStart"
    case .stepFinish: kind = "stepFinish"
    case .snapshot: kind = "snapshot"
    }
    return "m:\(messageID)#p:\(kind)#i:\(index)"
  }
}

extension ChatFeature.State {
  mutating func rebuildDerivedState() {
    let result = ChatMessageMapper.buildMessages(
      from: messages
    )
    exyteMessages = result.messages
    enhancedMessageParts = result.enhancedParts
    identifiedEnhancedMessageParts = result.identifiedParts
    unsupportedPartKinds = result.unsupportedParts
  }
}
