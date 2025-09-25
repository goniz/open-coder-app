import ComposableArchitecture
import Foundation

extension ChatFeature {
  func handleTask(state: inout State) -> Effect<Action> {
    guard let sessionID = state.sessionID,
          let serverURL = state.serverURL else {
      state.errorMessage = "Select a session to start chatting."
      return .none
    }

    state.isLoading = true
    state.errorMessage = nil
    return loadMessagesEffect(sessionID: sessionID, serverURL: serverURL)
  }

  func handleSendMessage(state: inout State) -> Effect<Action> {
    handleSendDraft(state: &state, draft: state.draft)
  }

  func handleSendDraft(state: inout State, draft: ChatDraftState) -> Effect<Action> {
    guard let sessionID = state.sessionID,
          let serverURL = state.serverURL else {
      state.errorMessage = "Select a session before sending messages."
      return .none
    }

    if draft.hasUnsupportedAttachments {
      state.errorMessage = "Attachments are not supported yet."
      return .none
    }

    let trimmedText = draft.trimmedText
    guard !trimmedText.isEmpty else {
      return .none
    }

    let messageID = draft.id ?? UUID().uuidString
    let parts: [MessagePart] = [.text(trimmedText)]
    let pendingMessage = OpenCodeMessage(
      id: messageID,
      sessionID: sessionID,
      parts: parts,
      timestamp: Date(),
      role: .user
    )

    state.messages.append(pendingMessage)
    state.exyteMessages.append(Message(
      id: messageID,
      user: MessageUser(senderId: "user", displayName: "You"),
      createdAt: Date(),
      text: trimmedText
    ))
    state.draft = ChatDraftState()
    state.isLoading = true

    return .run { send in
      do {
        try await sendMessage(sessionID: sessionID, serverURL: serverURL, message: pendingMessage)
        await send(.messageSendCompleted(messageID))
      } catch {
        await send(.messageSendFailed(messageID, error.localizedDescription))
      }
    }
  }

  func handleDraftUpdated(state: inout State, draft: ChatDraftState) -> Effect<Action> {
    state.draft = draft
    return .none
  }

  func handleMessageLifecycleActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .messagesLoaded(messages):
      state.messages = messages
      state.exyteMessages = messages.map { message in
        Message(
          id: message.id,
          user: MessageUser(senderId: message.role.rawValue, displayName: message.role.rawValue.capitalized),
          createdAt: message.timestamp,
          text: message.parts.compactMap { part in
            if case let .text(text) = part {
              return text
            }
            return nil
          }.joined()
        )
      }
      state.isLoading = false
      state.errorMessage = nil

    case let .messagesFailed(error):
      state.isLoading = false
      state.errorMessage = error

    case let .messageReceived(message):
      state.messages.append(message)
      state.exyteMessages.append(Message(
        id: message.id,
        user: MessageUser(senderId: message.role.rawValue, displayName: message.role.rawValue.capitalized),
        createdAt: message.timestamp,
        text: message.parts.compactMap { part in
          if case let .text(text) = part {
            return text
          }
          return nil
        }.joined()
      ))

    case let .messageSendCompleted(messageID):
      state.isLoading = false
      state.errorMessage = nil
      if let index = state.messages.firstIndex(where: { $0.id == messageID }) {
        state.messages[index].role = .assistant
        if let exyteIndex = state.exyteMessages.firstIndex(where: { $0.id == messageID }) {
          state.exyteMessages[exyteIndex].user = MessageUser(senderId: "assistant", displayName: "Assistant")
        }
      }

    case let .messageSendFailed(messageID, error):
      state.isLoading = false
      state.errorMessage = error
      if let index = state.messages.firstIndex(where: { $0.id == messageID }) {
        state.messages.remove(at: index)
      }
      if let exyteIndex = state.exyteMessages.firstIndex(where: { $0.id == messageID }) {
        state.exyteMessages.remove(at: exyteIndex)
      }

    case let .loadMoreCompleted(messages, hasMore):
      state.messages.insert(contentsOf: messages, at: 0)
      state.exyteMessages.insert(contentsOf: messages.map { message in
        Message(
          id: message.id,
          user: MessageUser(senderId: message.role.rawValue, displayName: message.role.rawValue.capitalized),
          createdAt: message.timestamp,
          text: message.parts.compactMap { part in
            if case let .text(text) = part {
              return text
            }
            return nil
          }.joined()
        )
      }, at: 0)
      state.canLoadMoreMessages = hasMore
      state.isLoadingMoreMessages = false

    case let .loadMoreFailed(error):
      state.isLoadingMoreMessages = false
      state.errorMessage = error

    default:
      return .none
    }
    return .none
  }

  func handleUpdateSession(state: inout State, sessionID: String) -> Effect<Action> {
    state.sessionID = sessionID
    state.messages = []
    state.exyteMessages = []
    state.pendingMessageIDs = []
    state.unsupportedPartKinds = []
    state.errorMessage = nil
    return .none
  }

  func handleSessionActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .fetchSessions:
      return .run { send in
        await send(.sessionsLoaded([]))
      }

    case let .sessionsLoaded(sessions):
      state.sessions = sessions

    case let .sessionsFailed(error):
      state.errorMessage = error

    case let .selectSession(sessionID):
      state.sessionID = sessionID
      state.messages = []
      state.exyteMessages = []
      state.pendingMessageIDs = []
      state.unsupportedPartKinds = []
      state.errorMessage = nil

    case .newSession:
      state.isCreatingSession = true

    case let .sessionCreated(session):
      state.sessions.append(session)
      state.isCreatingSession = false

    case let .sessionCreationFailed(error):
      state.isCreatingSession = false
      state.errorMessage = error

    default:
      return .none
    }
    return .none
  }

  func handleLoadMore(state: inout State) -> Effect<Action> {
    guard let sessionID = state.sessionID,
          let serverURL = state.serverURL,
          state.canLoadMoreMessages,
          !state.isLoadingMoreMessages else {
      return .none
    }

    state.isLoadingMoreMessages = true
    return loadMessagesEffect(sessionID: sessionID, serverURL: serverURL, isLoadMore: true)
  }

  func handleMediaPickerPresented(state: inout State, isPresented: Bool) -> Effect<Action> {
    state.mediaPicker.isPresented = isPresented
    return .none
  }

  func handleMediaPickerAttachmentsUpdated(state: inout State, count: Int) -> Effect<Action> {
    state.mediaPicker.selectedAttachmentCount = count
    return .none
  }
}
