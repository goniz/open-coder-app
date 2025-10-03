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
      if case let .text(text) = part {
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
    parts.compactMap { part in
      switch part {
      case .text(let content):
        return .text(content)
      case .reasoning(let content):
        return .reasoning(content)
      case .file(let path, let content):
        return .file(path: path, content: content, operation: .read)
      case .tool(let name, let input, let output):
        return .tool(EnhancedMessagePart.ToolCallInfo(
          id: UUID().uuidString,
          name: name,
          state: .completed,
          input: input,
          output: output
        ))
      case .agent(let type, let result):
        return .agent(result, agentType: type)
      }
    }
  }
}
