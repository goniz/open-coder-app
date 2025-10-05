import Protocols
import ExyteChat
import Foundation

enum ChatMessageMapper {
  struct BuildResult {
    var messages: [Message]
    var enhancedParts: [String: [EnhancedMessagePart]]
    var unsupportedParts: Set<ChatUnsupportedMessagePartKind>
  }

  struct MessageResult {
    let message: Message
    let enhancedParts: [EnhancedMessagePart]
    let unsupportedParts: Set<ChatUnsupportedMessagePartKind>
  }

  struct ContentResult {
    let text: String
    let enhancedParts: [EnhancedMessagePart]
    let unsupportedParts: Set<ChatUnsupportedMessagePartKind>
  }
  static func buildMessages(
    from messages: [OpenCodeMessage],
    pendingMessageIDs: Set<String>
  ) -> BuildResult {
    messages.reduce(into: BuildResult(
      messages: [],
      enhancedParts: [:],
      unsupportedParts: []
    )) { result, message in
      let mapped = map(message: message, isPending: pendingMessageIDs.contains(message.id))
      result.messages.append(mapped.message)
      if !mapped.enhancedParts.isEmpty {
        result.enhancedParts[message.id] = mapped.enhancedParts
      }
      result.unsupportedParts.formUnion(mapped.unsupportedParts)
    }
  }

  private static func map(
    message: OpenCodeMessage,
    isPending: Bool
  ) -> MessageResult {
    let content = textAndEnhancedParts(from: message.parts)
    let user = user(for: message.role, message: message)
    let status = status(for: message.role, isPending: isPending)

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
    case let .agent(agentType, content, _):
      return (nil, .agent(content, agentType: agentType))
    case let .tool(name, input, output, error, _):
      return (nil, createToolEnhancedPart(name: name, input: input, output: output, error: error))
    case let .patch(hash, files, _):
      return (nil, createPatchEnhancedPart(hash: hash, files: files))
    case let .stepStart(id):
      return (nil, .stepStart("Processing step", stepID: id ?? ""))
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

  private static func createPatchEnhancedPart(hash: String, files: [String]) -> EnhancedMessagePart {
    let title = "Patch (\(files.count) file\(files.count == 1 ? "" : "s"))"
    let filesText = files.joined(separator: "\n")
    return .patch(title, filePath: "Hash: \(hash)", diff: filesText)
  }

  private static func createStepFinishEnhancedPart(
    cost: Double,
    inputTokens: Double,
    outputTokens: Double,
    id: String?
  ) -> EnhancedMessagePart {
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
      case .stepStart(let text, _):
        return "▶️ \(text)"
      case .stepFinish(let text, _, _):
        return "✅ \(text)"
      case .snapshot(let text, _):
        return "📸 \(text)"
      case .patch(let text, _, _):
        return "🔧 \(text)"
      case .reasoning:
        return "💭 Reasoning"
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

  private static func status(for role: MessageRole, isPending: Bool) -> Message.Status? {
    switch role {
    case .user:
      return isPending ? .sending : .sent
    case .assistant:
      return .read
    case .system:
      return nil
    }
  }
}

extension ChatFeature.State {
  mutating func rebuildDerivedState() {
    let result = ChatMessageMapper.buildMessages(
      from: messages,
      pendingMessageIDs: pendingMessageIDs
    )
    exyteMessages = result.messages
    enhancedMessageParts = result.enhancedParts
    unsupportedPartKinds = result.unsupportedParts
  }
}
