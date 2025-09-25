import ComposableArchitecture
import Foundation
import Protocols
import ExyteChat
import Models

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
      user: User(id: "user", name: "You", avatarURL: nil, isCurrentUser: true),
      createdAt: Date(),
      text: trimmedText
    ))
    state.draft = ChatDraftState()
    state.isLoading = true

    return .run { [openCodeAPIFactory] send in
      do {
        let configuration = OpenCodeConfiguration(serverURL: serverURL)
        let apiClient = openCodeAPIFactory.make(configuration)
        _ = try await apiClient.sendMessage(sessionID: sessionID, parts: pendingMessage.parts)
        await send(.messageSendCompleted(messageID: messageID))
      } catch {
        await send(.messageSendFailed(messageID: messageID, error: error.localizedDescription))
      }
    }
  }

  func handleDraftUpdated(state: inout State, draft: ChatDraftState) -> Effect<Action> {
    state.draft = draft
    return .none
  }

  func handleUpdateSession(state: inout State, sessionID: String?) -> Effect<Action> {
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
      state.isLoadingSessions = true

    case let .sessionCreated(session):
      state.sessions.append(session)
      state.isLoadingSessions = false

    case let .sessionCreationFailed(error):
      state.isLoadingSessions = false
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

  func handleMediaPickerActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .mediaPickerPresented(isPresented):
      return handleMediaPickerPresented(state: &state, isPresented: isPresented)
    case let .mediaPickerAttachmentsUpdated(count):
      return handleMediaPickerAttachmentsUpdated(state: &state, count: count)
    default:
      return .none
    }
  }

  func handleCoreMessageActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .messagesLoaded, .messagesFailed, .messageReceived,
         .messageSendCompleted, .messageSendFailed, .loadMoreCompleted, .loadMoreFailed:
      return handleMessageLifecycleActions(state: &state, action: action)
    case let .updateSession(sessionID):
      return handleUpdateSession(state: &state, sessionID: sessionID)
    default:
      return .none
    }
  }

  private func loadMessagesEffect(sessionID: String, serverURL: URL, isLoadMore: Bool = false) -> Effect<Action> {
    .run { [openCodeAPIFactory] send in
      do {
        let configuration = OpenCodeConfiguration(serverURL: serverURL)
        let apiClient = openCodeAPIFactory.make(configuration)
        let messages = try await apiClient.getMessages(sessionID: sessionID)
        if isLoadMore {
          await send(.loadMoreCompleted(messages, hasMore: false))
        } else {
          await send(.messagesLoaded(messages))
        }
      } catch {
        if isLoadMore {
          await send(.loadMoreFailed(error.localizedDescription))
        } else {
          await send(.messagesFailed(error.localizedDescription))
        }
      }
    }
  }

  func handleServerURLUpdated(state: inout State, url: URL?) -> Effect<Action> {
    state.serverURL = url
    state.messages = []
    state.exyteMessages = []
    state.pendingMessageIDs = []
    state.unsupportedPartKinds = []
    state.errorMessage = nil
    return .none
  }

  func handleMessageDraftActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .sendMessage:
      return .send(.sendDraft(state.draft))
    case let .sendDraft(draft):
      return handleSendDraft(state: &state, draft: draft)
    case let .draftUpdated(draft):
      return handleDraftUpdated(state: &state, draft: draft)
    default:
      return .none
    }
  }
}
