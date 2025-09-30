import ComposableArchitecture
import Foundation
import Protocols
import ExyteChat
import Models

private actor SharedAPIClientCache {
  static let shared = SharedAPIClientCache()

  private var clients: [URL: OpenCodeAPIClientProtocol] = [:]

  private init() {}

  func client(for serverURL: URL, factory: OpenCodeAPIClientFactoryProtocol) -> OpenCodeAPIClientProtocol {
    if let cachedClient = clients[serverURL] {
      return cachedClient
    }

    let configuration = OpenCodeConfiguration(serverURL: serverURL)
    let client = factory.make(configuration)
    clients[serverURL] = client
    return client
  }

  func removeClient(for serverURL: URL) {
    clients.removeValue(forKey: serverURL)
  }

  func clearCache() {
    clients.removeAll()
  }
}

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
      user: User(id: "user", name: "You", avatarURL: nil, avatarCacheKey: nil, isCurrentUser: true),
      createdAt: Date(),
      text: trimmedText
    ))
    state.draft = ChatDraftState()
    state.isLoading = true

    return .run { send in
      @Dependency(\.openCodeAPIFactory) var factory
      do {
        let apiClient = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
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
      return handleFetchSessions(state: &state)
    case let .sessionsLoaded(sessions):
      return handleSessionsLoaded(state: &state, sessions: sessions)
    case let .sessionsFailed(error):
      return handleSessionsFailed(state: &state, error: error)
    case let .selectSession(sessionID):
      return handleSelectSession(state: &state, sessionID: sessionID)
    case .newSession:
      return handleNewSession(state: &state)
    case let .sessionCreated(session):
      return handleSessionCreated(state: &state, session: session)
    case let .sessionCreationFailed(error):
      return handleSessionCreationFailed(state: &state, error: error)
    default:
      return .none
    }
  }

  private func handleFetchSessions(state: inout State) -> Effect<Action> {
    guard let serverURL = state.serverURL else {
      return .run { send in
        await send(.sessionsFailed("No server URL configured"))
      }
    }

    state.isLoadingSessions = true
    return .run { send in
      @Dependency(\.openCodeAPIFactory) var factory
      do {
        let apiClient = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let sessions = try await apiClient.listSessions()
        await send(.sessionsLoaded(sessions))
      } catch {
        await send(.sessionsFailed(error.localizedDescription))
      }
    }
  }

  private func handleSessionsLoaded(state: inout State, sessions: [OpenCodeSession]) -> Effect<Action> {
    state.sessions = sessions
    state.isLoadingSessions = false
    return .none
  }

  private func handleSessionsFailed(state: inout State, error: String) -> Effect<Action> {
    state.errorMessage = error
    state.isLoadingSessions = false
    return .none
  }

  private func handleSelectSession(state: inout State, sessionID: String) -> Effect<Action> {
    state.sessionID = sessionID
    clearSessionState(state: &state)
    return .none
  }

  private func handleNewSession(state: inout State) -> Effect<Action> {
    guard let serverURL = state.serverURL else {
      return .run { send in
        await send(.sessionCreationFailed("No server URL configured"))
      }
    }

    state.isLoadingSessions = true
    return .run { send in
      @Dependency(\.openCodeAPIFactory) var factory
      do {
        let apiClient = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let session = try await apiClient.createSession()
        await send(.sessionCreated(session))
      } catch {
        await send(.sessionCreationFailed(error.localizedDescription))
      }
    }
  }

  private func handleSessionCreated(state: inout State, session: OpenCodeSession) -> Effect<Action> {
    state.sessions.append(session)
    state.sessionID = session.id
    state.isLoadingSessions = false
    clearSessionState(state: &state)
    return .none
  }

  private func handleSessionCreationFailed(state: inout State, error: String) -> Effect<Action> {
    state.isLoadingSessions = false
    state.errorMessage = error
    return .none
  }

  private func clearSessionState(state: inout State) {
    state.messages = []
    state.exyteMessages = []
    state.pendingMessageIDs = []
    state.unsupportedPartKinds = []
    state.errorMessage = nil
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
    .run { send in
      @Dependency(\.openCodeAPIFactory) var factory
      do {
        let apiClient = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
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
    let oldURL = state.serverURL
    state.serverURL = url
    state.messages = []
    state.exyteMessages = []
    state.pendingMessageIDs = []
    state.unsupportedPartKinds = []
    state.errorMessage = nil

    // Clear cached client for old URL if it changed
    if let oldURL = oldURL, oldURL != url {
      return .run { _ in
        await SharedAPIClientCache.shared.removeClient(for: oldURL)
      }
    }

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
