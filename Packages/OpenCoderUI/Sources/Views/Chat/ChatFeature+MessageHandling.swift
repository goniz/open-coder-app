import ComposableArchitecture
import Foundation
import Protocols
import ExyteChat

extension ChatFeature {
  func handleMessageLifecycleActions(state: inout State, action: Action) -> Effect<Action> {
    if case let .messageDetailsLoaded(message) = action {
      return handleMessageDetailsLoaded(state: &state, message: message)
    }
    if case let .messageDetailsFailed(messageID, error) = action {
      return handleMessageDetailsFailed(state: &state, messageID: messageID, error: error)
    }

    switch action {
    case let .messagesLoaded(messages):
      return handleMessagesLoaded(state: &state, messages: messages)
    case let .messagesFailed(error):
      return handleMessagesFailed(state: &state, error: error)
    case let .messageReceived(message):
      return handleMessageReceived(state: &state, message: message)
    case let .messageUpdated(message):
      return handleMessageUpdated(state: &state, message: message)
    case let .messagePartUpdated(sessionID, messageID, partID, part):
      return handleMessagePartUpdated(
        state: &state, sessionID: sessionID, messageID: messageID, partID: partID, part: part
      )
    case let .messageSendSucceeded(tempID, message):
      return handleMessageSendSucceeded(state: &state, tempID: tempID, message: message)
    default:
      return .none
    }
  }

  func handleMessagesLoaded(state: inout State, messages: [OpenCodeMessage]) -> Effect<Action> {
    state.messages = messages.sorted(by: messageSortComparator)
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
    processIncomingMessage(state: &state, message: message, allowEnrichment: true)
  }

  func handleMessageUpdated(state: inout State, message: OpenCodeMessage) -> Effect<Action> {
    processIncomingMessage(state: &state, message: message, allowEnrichment: true)
  }

  func handleMessagePartUpdated(
    state: inout State,
    sessionID: String,
    messageID: String,
    partID: String,
    part: MessagePart
  ) -> Effect<Action> {
    if let currentSessionID = state.sessionID, currentSessionID != sessionID {
      return .none
    }

    if let messageIndex = state.messages.firstIndex(where: { $0.id == messageID }) {
      let message = state.messages[messageIndex]
      var updatedParts = message.parts

      if let partIndex = updatedParts.firstIndex(where: { $0.id == partID }) {
        updatedParts[partIndex] = part
      } else {
        updatedParts.append(part)
      }

      let updatedMessage = OpenCodeMessage(
        id: message.id,
        sessionID: message.sessionID,
        parts: updatedParts,
        timestamp: message.timestamp,
        role: message.role,
        modelID: message.modelID,
        providerID: message.providerID
      )

      state.messages[messageIndex] = updatedMessage
    } else {
      let placeholder = OpenCodeMessage(
        id: messageID,
        sessionID: sessionID,
        parts: [part],
        timestamp: Date(),
        role: .assistant
      )
      upsertMessage(placeholder, into: &state.messages)
    }

    state.rebuildDerivedState()
    return .none
  }

  func handleMessageSendCompleted(state: inout State, messageID: String) -> Effect<Action> {
    state.isLoading = false
    state.errorMessage = nil
    state.pendingMessageIDs.remove(messageID)
    state.rebuildDerivedState()
    return .none
  }

  func handleMessageDetailsLoaded(state: inout State, message: OpenCodeMessage) -> Effect<Action> {
    state.messagesAwaitingDetails.remove(message.id)
    return processIncomingMessage(state: &state, message: message, allowEnrichment: false)
  }

  func handleMessageDetailsFailed(state: inout State, messageID: String, error: String) -> Effect<Action> {
    state.messagesAwaitingDetails.remove(messageID)
    state.errorMessage = error
    return .none
  }

  func handleMessageSendFailed(state: inout State, messageID: String, error: String) -> Effect<Action> {
    state.isLoading = false
    state.errorMessage = error
    state.pendingMessageIDs.remove(messageID)
    if let index = state.messages.firstIndex(where: { $0.id == messageID }) {
      state.messages.remove(at: index)
    }
    if let exyteIndex = state.exyteMessages.firstIndex(where: { $0.id == messageID }) {
      state.exyteMessages.remove(at: exyteIndex)
    }
    state.rebuildDerivedState()
    return .none
  }

  func handleMessageSendSucceeded(
    state: inout State,
    tempID: String,
    message: OpenCodeMessage
  ) -> Effect<Action> {
    state.isLoading = false
    state.pendingMessageIDs.remove(tempID)

    if let tempIndex = state.messages.firstIndex(where: { $0.id == tempID }) {
      state.messages.remove(at: tempIndex)
    }

    return processIncomingMessage(state: &state, message: message, allowEnrichment: false)
  }

  func handleLoadMoreCompleted(
    state: inout State,
    messages: [OpenCodeMessage],
    hasMore: Bool
  ) -> Effect<Action> {
    messages.sorted(by: messageSortComparator).forEach { message in
      upsertMessage(message, into: &state.messages)
    }
    state.rebuildDerivedState()
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
    case .patch:
      return nil
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

  private func convertStepFinishPart(cost: Double, inputTokens: Double, outputTokens: Double) -> EnhancedMessagePart {
    let costText = String(format: "%.4f", cost)
    return .text("Step completed - Cost: $\(costText), Tokens: \(Int(inputTokens)) in / \(Int(outputTokens)) out")
  }

  func upsertMessage(_ message: OpenCodeMessage, into messages: inout [OpenCodeMessage]) {
    if let existingIndex = messages.firstIndex(where: { $0.id == message.id }) {
      messages[existingIndex] = message
      return
    }

    let insertionIndex = messages.firstIndex { candidate in
      messageSortComparator(message, candidate)
    } ?? messages.endIndex

    messages.insert(message, at: insertionIndex)
  }

  func messageSortComparator(_ lhs: OpenCodeMessage, _ rhs: OpenCodeMessage) -> Bool {
    if lhs.timestamp == rhs.timestamp {
      return lhs.id < rhs.id
    }
    return lhs.timestamp < rhs.timestamp
  }

  private func processIncomingMessage(
    state: inout State,
    message: OpenCodeMessage,
    allowEnrichment: Bool
  ) -> Effect<Action> {
    if let currentSessionID = state.sessionID, currentSessionID != message.sessionID {
      return .none
    }

    upsertMessage(message, into: &state.messages)
    state.pendingMessageIDs.remove(message.id)
    state.rebuildDerivedState()

    guard allowEnrichment,
          message.parts.isEmpty,
          let serverURL = state.serverURL,
          !state.messagesAwaitingDetails.contains(message.id) else {
      return .none
    }

    state.messagesAwaitingDetails.insert(message.id)
    let factory = self.openCodeAPIFactory
    return .run { send in
      do {
        let apiClient = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let fullMessage = try await apiClient.getMessage(
          sessionID: message.sessionID,
          messageID: message.id
        )
        await send(.messageDetailsLoaded(fullMessage))
      } catch {
        await send(.messageDetailsFailed(messageID: message.id, error: error.localizedDescription))
      }
    }
  }
}
