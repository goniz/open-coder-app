import ComposableArchitecture
import Protocols
import Dependencies
import Foundation
import Models

extension ChatFeature {
  func handleTask(state: inout State) -> Effect<Action> {
    guard let sessionID = state.sessionID,
      let serverURL = state.serverURL else { return .none }
    state.isLoading = true
    state.errorMessage = nil
    return loadMessagesEffect(sessionID: sessionID, serverURL: serverURL)
  }

  func handleSendMessage(state: inout State) -> Effect<Action> {
    let draftText = state.currentMessage
    state.currentMessage = ""
    let draft = ChatDraftState(text: draftText)
    return handleSendDraft(state: &state, draft: draft)
  }

  func handleSendDraft(state: inout State, draft: ChatDraftState) -> Effect<Action> {
    guard let sessionID = state.sessionID,
      let serverURL = state.serverURL else {
      return .none
    }

    if draft.hasUnsupportedAttachments || draft.attachmentCount > 0 {
      state.errorMessage = "Attachments are not supported yet."
      return .none
    }

    let trimmedText = draft.trimmedText
    guard !trimmedText.isEmpty else {
      return .none
    }

    state.isLoading = true
    state.errorMessage = nil

    let userMessage = OpenCodeMessage(
      id: UUID().uuidString,
      sessionID: sessionID,
      parts: [.text(trimmedText)],
      timestamp: Date(),
      role: .user
    )

    state.messages.append(userMessage)
    state.pendingMessageIDs.insert(userMessage.id)
    state.draft = .init()
    state.rebuildDerivedState()

    let baseConfiguration = openCodeConfiguration
    let configuration = OpenCodeConfiguration(
      serverURL: serverURL,
      timeout: baseConfiguration.timeout,
      retryCount: baseConfiguration.retryCount
    )
    let apiClient = openCodeAPIFactory.make(configuration)

    let parts: [MessagePart] = [.text(trimmedText)]

    return .run { send in
      do {
        let response = try await apiClient.sendMessage(
          sessionID: sessionID,
          parts: parts
        )
        await send(.messageSendCompleted(messageID: userMessage.id))
        await send(.messageReceived(response))
      } catch {
        await send(
          .messageSendFailed(
            messageID: userMessage.id,
            error: error.localizedDescription
          )
        )
      }
    }
  }

  func handleDraftUpdated(state: inout State, draft: ChatDraftState) -> Effect<Action> {
    state.draft = draft
    return .none
  }

  func handleMessagesLoaded(state: inout State, messages: [OpenCodeMessage]) -> Effect<Action> {
    state.messages = messages
    state.isLoading = false
    state.isLoadingMoreMessages = false
    state.canLoadMoreMessages = false
    let validPending = Set(messages.map(\.id))
    state.pendingMessageIDs = state.pendingMessageIDs.intersection(validPending)
    state.errorMessage = nil
    state.rebuildDerivedState()
    return .none
  }

  func handleMessagesFailed(state: inout State, errorMessage: String) -> Effect<Action> {
    state.isLoading = false
    state.isLoadingMoreMessages = false
    state.errorMessage = errorMessage
    return .none
  }

  func handleMessageReceived(state: inout State, message: OpenCodeMessage) -> Effect<Action> {
    state.messages.append(message)
    state.isLoading = false
    state.rebuildDerivedState()
    return .none
  }

  func handleMessageSendCompleted(state: inout State, messageID: String) -> Effect<Action> {
    state.pendingMessageIDs.remove(messageID)
    state.rebuildDerivedState()
    return .none
  }

  func handleMessageSendFailed(
    state: inout State,
    messageID: String,
    errorMessage: String
  ) -> Effect<Action> {
    state.pendingMessageIDs.remove(messageID)
    state.isLoading = false
    state.errorMessage = errorMessage
    state.rebuildDerivedState()
    return .none
  }

  func handleUpdateSession(state: inout State, sessionID: String?) -> Effect<Action> {
    guard state.sessionID != sessionID else { return .none }
    state.sessionID = sessionID
    state.messages = []
    state.errorMessage = nil
    state.pendingMessageIDs.removeAll()
    state.draft = .init()
    state.rebuildDerivedState()

    guard let sessionID, let serverURL = state.serverURL else { return .none }
    state.isLoading = true
    return loadMessagesEffect(sessionID: sessionID, serverURL: serverURL)
  }

  func handleMessageLifecycleActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .messagesLoaded(messages):
      return handleMessagesLoaded(state: &state, messages: messages)

    case let .messagesFailed(errorMessage):
      return handleMessagesFailed(state: &state, errorMessage: errorMessage)

    case let .messageReceived(message):
      return handleMessageReceived(state: &state, message: message)

    case let .messageSendCompleted(messageID):
      return handleMessageSendCompleted(state: &state, messageID: messageID)

    case let .messageSendFailed(messageID, errorMessage):
      return handleMessageSendFailed(state: &state, messageID: messageID, errorMessage: errorMessage)

    case let .loadMoreCompleted(messages, hasMore):
      return handleLoadMoreCompleted(state: &state, messages: messages, hasMore: hasMore)

    case let .loadMoreFailed(errorMessage):
      return handleLoadMoreFailed(state: &state, errorMessage: errorMessage)

    default:
      return .none
    }
  }

  func handleMediaPickerActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .mediaPickerPresented(isPresented):
      state.mediaPicker.isPresented = isPresented
      return .none

    case let .mediaPickerAttachmentsUpdated(count):
      state.mediaPicker.selectedAttachmentCount = count
      return .none

    default:
      return .none
    }
  }

  func handleSessionActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .fetchSessions:
      return handleFetchSessions(state: &state)

    case let .sessionsLoaded(sessions):
      return handleSessionsLoaded(state: &state, sessions: sessions)

    case let .sessionsFailed(errorMessage):
      return handleSessionsFailed(state: &state, errorMessage: errorMessage)

    case let .selectSession(sessionID):
      return handleSelectSession(state: &state, sessionID: sessionID)

    case .newSession:
      return handleNewSession(state: &state)

    case let .sessionCreated(session):
      return handleSessionCreated(state: &state, session: session)

    case let .sessionCreationFailed(errorMessage):
      return handleSessionCreationFailed(state: &state, errorMessage: errorMessage)

    default:
      return .none
    }
  }

  func handleFetchSessions(state: inout State) -> Effect<Action> {
    guard let serverURL = state.serverURL else {
      state.errorMessage = "Waiting for workspace connection..."
      return .none
    }
    state.isLoadingSessions = true
    state.errorMessage = nil

    let baseConfiguration = openCodeConfiguration
    let configuration = OpenCodeConfiguration(
      serverURL: serverURL,
      timeout: baseConfiguration.timeout,
      retryCount: baseConfiguration.retryCount
    )
    let apiClient = openCodeAPIFactory.make(configuration)

    return .run { send in
      do {
        let sessions = try await apiClient.listSessions()
        await send(.sessionsLoaded(sessions))
      } catch {
        await send(.sessionsFailed(error.localizedDescription))
      }
    }
  }

  func handleSessionsLoaded(state: inout State, sessions: [OpenCodeSession]) -> Effect<Action> {
    state.sessions = sessions
    state.isLoadingSessions = false
    state.errorMessage = nil

    if state.sessionID == nil, let latestSession = sessions.max(by: { $0.updatedAt < $1.updatedAt }) {
      return .send(.selectSession(latestSession.id))
    }

    return .none
  }

  func handleSessionsFailed(state: inout State, errorMessage: String) -> Effect<Action> {
    state.isLoadingSessions = false
    state.errorMessage = errorMessage
    return .none
  }

  func handleSelectSession(state: inout State, sessionID: String) -> Effect<Action> {
    return .send(.updateSession(sessionID))
  }

  func handleNewSession(state: inout State) -> Effect<Action> {
    guard let serverURL = state.serverURL else { return .none }
    state.isLoading = true
    state.errorMessage = nil

    let baseConfiguration = openCodeConfiguration
    let configuration = OpenCodeConfiguration(
      serverURL: serverURL,
      timeout: baseConfiguration.timeout,
      retryCount: baseConfiguration.retryCount
    )
    let apiClient = openCodeAPIFactory.make(configuration)

    return .run { send in
      do {
        let session = try await apiClient.createSession()
        await send(.sessionCreated(session))
      } catch {
        await send(.sessionCreationFailed(error.localizedDescription))
      }
    }
  }

  func handleSessionCreated(state: inout State, session: OpenCodeSession) -> Effect<Action> {
    state.isLoading = false
    state.sessions.append(session)
    return .send(.selectSession(session.id))
  }

  func handleSessionCreationFailed(state: inout State, errorMessage: String) -> Effect<Action> {
    state.isLoading = false
    state.errorMessage = errorMessage
    return .none
  }

  func handleLoadMore(state: inout State) -> Effect<Action> {
    guard let sessionID = state.sessionID,
      let serverURL = state.serverURL else {
      return .none
    }

    guard !state.isLoadingMoreMessages else {
      return .none
    }

    state.isLoadingMoreMessages = true
    state.errorMessage = nil

    let baseConfiguration = openCodeConfiguration
    let configuration = OpenCodeConfiguration(
      serverURL: serverURL,
      timeout: baseConfiguration.timeout,
      retryCount: baseConfiguration.retryCount
    )
    let apiClient = openCodeAPIFactory.make(configuration)

    return .run { send in
      do {
        let messages = try await apiClient.getMessages(sessionID: sessionID)
        await send(.loadMoreCompleted(messages, hasMore: false))
      } catch {
        await send(.loadMoreFailed(error.localizedDescription))
      }
    }
  }

  func handleLoadMoreCompleted(
    state: inout State,
    messages: [OpenCodeMessage],
    hasMore: Bool
  ) -> Effect<Action> {
    state.isLoadingMoreMessages = false
    state.canLoadMoreMessages = hasMore
    state.messages = messages
    state.errorMessage = nil
    state.rebuildDerivedState()
    return .none
  }

  func handleLoadMoreFailed(state: inout State, errorMessage: String) -> Effect<Action> {
    state.isLoadingMoreMessages = false
    state.errorMessage = errorMessage
    return .none
  }
}
