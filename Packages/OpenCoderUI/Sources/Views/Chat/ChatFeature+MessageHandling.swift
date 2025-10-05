import ComposableArchitecture
import Foundation
import Protocols
import ExyteChat

extension ChatFeature {
  func handleMessageLifecycleActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .messagesLoaded(messages):
      return handleMessagesLoaded(state: &state, messages: messages)
    case let .messagesFailed(error):
      return handleMessagesFailed(state: &state, error: error)
    case let .messageReceived(message):
      return handleMessageReceived(state: &state, message: message)
    case let .messageSendCompleted(messageID):
      return handleMessageSendCompleted(state: &state, messageID: messageID)
    case let .messageSendFailed(messageID, error):
      return handleMessageSendFailed(state: &state, messageID: messageID, error: error)
    case let .loadMoreCompleted(messages, hasMore):
      return handleLoadMoreCompleted(state: &state, messages: messages, hasMore: hasMore)
    case let .loadMoreFailed(error):
      return handleLoadMoreFailed(state: &state, error: error)
    default:
      return .none
    }
  }

  func handleMessagesLoaded(state: inout State, messages: [OpenCodeMessage]) -> Effect<Action> {
    state.messages = messages
    state.rebuildDerivedState()
    state.isLoading = false
    state.errorMessage = nil
    return .none
  }

  func handleMessagesFailed(state: inout State, error: String) -> Effect<Action> {
    state.isLoading = false
    state.errorMessage = error
    return .none
  }

  func handleMessageReceived(state: inout State, message: OpenCodeMessage) -> Effect<Action> {
    state.messages.append(message)
    state.rebuildDerivedState()
    return .none
  }

  func handleMessageSendCompleted(state: inout State, messageID: String) -> Effect<Action> {
    state.isLoading = false
    state.errorMessage = nil
    if let exyteIndex = state.exyteMessages.firstIndex(where: { $0.id == messageID }) {
      state.exyteMessages[exyteIndex].user = User(
        id: "assistant",
        name: "Assistant",
        avatarURL: nil,
        avatarCacheKey: nil,
        isCurrentUser: false
      )
    }
    return .none
  }

  func handleMessageSendFailed(state: inout State, messageID: String, error: String) -> Effect<Action> {
    state.isLoading = false
    state.errorMessage = error
    if let index = state.messages.firstIndex(where: { $0.id == messageID }) {
      state.messages.remove(at: index)
    }
    if let exyteIndex = state.exyteMessages.firstIndex(where: { $0.id == messageID }) {
      state.exyteMessages.remove(at: exyteIndex)
    }
    return .none
  }

  func handleLoadMoreCompleted(
    state: inout State,
    messages: [OpenCodeMessage],
    hasMore: Bool
  ) -> Effect<Action> {
    state.messages.insert(contentsOf: messages, at: 0)
    state.exyteMessages.insert(contentsOf: messages.map { createEnhancedMessage(from: $0) }, at: 0)
    state.canLoadMoreMessages = hasMore
    state.isLoadingMoreMessages = false
    return .none
  }

  func handleLoadMoreFailed(state: inout State, error: String) -> Effect<Action> {
    state.isLoadingMoreMessages = false
    state.errorMessage = error
    return .none
  }

  // MARK: - Enhanced Message Creation

  private func createEnhancedMessage(from message: OpenCodeMessage) -> Message {
    // Convert parts to enhanced parts for better rendering
    _ = convertToEnhancedParts(message.parts)

    // Create base message with enhanced content
    let baseText = message.parts.compactMap { part in
      if case let .text(text, _) = part {
        return text
      }
      return nil
    }.joined()

    let enhancedMessage = Message(
      id: message.id,
      user: User(
        id: message.role.rawValue,
        name: message.role.rawValue.capitalized,
        avatarURL: nil,
        avatarCacheKey: nil,
        isCurrentUser: message.role == .user
      ),
      createdAt: message.timestamp,
      text: baseText
    )

    // Store enhanced parts in message metadata for retrieval by ChatMessageView
    // This is a workaround since we can't extend Message directly
    return enhancedMessage
  }

  private func convertToEnhancedParts(_ parts: [MessagePart]) -> [EnhancedMessagePart] {
    parts.compactMap { convertToEnhancedPart($0) }
  }

  private func convertToEnhancedPart(_ part: MessagePart) -> EnhancedMessagePart? {
    switch part {
    case .text(let content, _):
      return .text(content)
    case .reasoning(let content, _):
      return .reasoning(content)
    case .file(let path, let content, _):
      return .file(path: path, content: content, operation: .read)
    case .tool(let name, let input, let output, let error, _):
      return convertToolPart(name: name, input: input, output: output, error: error)
    case .agent(let type, let result, _):
      return .agent(result, agentType: type)
    case .patch(let hash, let files, _):
      return convertPatchPart(hash: hash, files: files)
    case .stepStart:
      return nil
    case .stepFinish(let cost, let inputTokens, let outputTokens, _):
      return convertStepFinishPart(cost: cost, inputTokens: inputTokens, outputTokens: outputTokens)
    case .snapshot(let content, _):
      return .text("Snapshot: \(content)")
    }
  }

  private func convertToolPart(
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
    return .tool(EnhancedMessagePart.ToolCallInfo(
      id: UUID().uuidString,
      name: name,
      state: state,
      input: input,
      output: output,
      error: error
    ))
  }

  private func convertPatchPart(hash: String, files: [String]) -> EnhancedMessagePart {
    let title = "Patch (\(files.count) file\(files.count == 1 ? "" : "s"))"
    let filesText = files.joined(separator: "\n")
    return .patch(title, filePath: "Hash: \(hash)", diff: filesText)
  }

  private func convertStepFinishPart(cost: Double, inputTokens: Double, outputTokens: Double) -> EnhancedMessagePart {
    let costText = String(format: "%.4f", cost)
    return .text("Step completed - Cost: $\(costText), Tokens: \(Int(inputTokens)) in / \(Int(outputTokens)) out")
  }
}
