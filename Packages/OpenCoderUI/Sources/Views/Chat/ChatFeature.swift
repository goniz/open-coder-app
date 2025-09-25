import ComposableArchitecture
import Protocols
import Dependencies
import ExyteChat
import Foundation
import Models

public enum ChatUnsupportedMessagePartKind: String, Hashable, Sendable {
  case file
  case agent
  case tool
}

public struct ChatDraftState: Equatable, Sendable {
  public var id: String?
  public var text: String
  public var attachmentCount: Int
  public var hasUnsupportedAttachments: Bool

  public init(
    id: String? = nil,
    text: String = "",
    attachmentCount: Int = 0,
    hasUnsupportedAttachments: Bool = false
  ) {
    self.id = id
    self.text = text
    self.attachmentCount = attachmentCount
    self.hasUnsupportedAttachments = hasUnsupportedAttachments
  }

  public var trimmedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var isEmpty: Bool {
    trimmedText.isEmpty && attachmentCount == 0
  }
}

public struct ChatMediaPickerState: Equatable, Sendable {
  public var isPresented = false
  public var selectedAttachmentCount = 0
}

@Reducer
public struct ChatFeature {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var messages: [OpenCodeMessage] = []
    public var exyteMessages: [Message] = []
    public var unsupportedPartKinds: Set<ChatUnsupportedMessagePartKind> = []
    public var currentMessage = ""
    public var isLoading = false
    public var isLoadingMoreMessages = false
    public var canLoadMoreMessages = false
    public var isAssistantTyping = false
    public var errorMessage: String?
    public var sessionID: String?
    public var serverURL: URL?
    public var sessions: [OpenCodeSession] = []
    public var isLoadingSessions = false
    public var pendingMessageIDs: Set<String> = []
    public var draft = ChatDraftState()
    public var mediaPicker = ChatMediaPickerState()
    public var currentSessionTitle: String {
      guard let sessionID = sessionID,
            let session = sessions.first(where: { $0.id == sessionID }) else {
        return "Select Session"
      }
      return session.displayTitle
    }

    public init(sessionID: String? = nil, serverURL: URL? = nil) {
      self.sessionID = sessionID
      self.serverURL = serverURL
    }
  }

  public enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case task
    case sendMessage
    case sendDraft(ChatDraftState)
    case draftUpdated(ChatDraftState)
    case serverURLUpdated(URL?)
    case messagesLoaded([OpenCodeMessage])
    case messagesFailed(String)
    case messageReceived(OpenCodeMessage)
    case messageSendCompleted(messageID: String)
    case messageSendFailed(messageID: String, error: String)
    case updateSession(String?)
    case fetchSessions
    case sessionsLoaded([OpenCodeSession])
    case sessionsFailed(String)
    case selectSession(String)
    case newSession
    case sessionCreated(OpenCodeSession)
    case sessionCreationFailed(String)
    case loadMore
    case loadMoreCompleted([OpenCodeMessage], hasMore: Bool)
    case loadMoreFailed(String)
    case mediaPickerPresented(Bool)
    case mediaPickerAttachmentsUpdated(Int)
    case messageMenuAction(DefaultMessageMenuAction, messageID: String)
  }

  @Dependency(\.openCodeAPIFactory) var openCodeAPIFactory
  @Dependency(\.openCodeConfiguration) var openCodeConfiguration

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce(core)
  }

  public func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .binding:
      return .none

    case .messageMenuAction:
      // TODO: implement menu actions (copy, delete, etc.)
      return .none

    case let .serverURLUpdated(url):
      state.serverURL = url
      if url == nil {
        state.sessionID = nil
        state.messages = []
        state.exyteMessages = []
        state.pendingMessageIDs = []
        state.unsupportedPartKinds = []
        state.errorMessage = nil
      }
      return .none

    case .task:
      return handleTask(state: &state)

    case .sendMessage:
      return handleSendMessage(state: &state)

    case let .sendDraft(draft):
      return handleSendDraft(state: &state, draft: draft)

    case let .draftUpdated(draft):
      return handleDraftUpdated(state: &state, draft: draft)

    case .messagesLoaded,
         .messagesFailed,
         .messageReceived,
         .messageSendCompleted,
         .messageSendFailed,
         .loadMoreCompleted,
         .loadMoreFailed:
      return handleMessageLifecycleActions(state: &state, action: action)

    case let .updateSession(sessionID):
      return handleUpdateSession(state: &state, sessionID: sessionID)

    case .fetchSessions, .sessionsLoaded, .sessionsFailed, .selectSession,
         .newSession, .sessionCreated, .sessionCreationFailed:
      return handleSessionActions(state: &state, action: action)

    case .loadMore:
      return handleLoadMore(state: &state)

    case let .mediaPickerPresented(isPresented):
      return handleMediaPickerPresented(state: &state, isPresented: isPresented)

    case let .mediaPickerAttachmentsUpdated(count):
      return handleMediaPickerAttachmentsUpdated(state: &state, count: count)
    }
  }

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
    state.pendingMessageIDs.insert(messageID)
    state.draft = ChatDraftState()
    state.currentMessage = ""
    state.errorMessage = nil
    state.rebuildDerivedState()

    let baseConfiguration = openCodeConfiguration
    let configuration = OpenCodeConfiguration(
      serverURL: serverURL,
      timeout: baseConfiguration.timeout,
      retryCount: baseConfiguration.retryCount
    )
    let apiClient = openCodeAPIFactory.make(configuration)

    return .run { [messageID, sessionID, parts] send in
      do {
        let response = try await apiClient.sendMessage(sessionID: sessionID, parts: parts)
        await send(.messageSendCompleted(messageID: messageID))
        await send(.messageReceived(response))
      } catch {
        await send(.messageSendFailed(messageID: messageID, error: error.localizedDescription))
      }
    }
  }

  func handleDraftUpdated(state: inout State, draft: ChatDraftState) -> Effect<Action> {
    state.draft = draft
    state.currentMessage = draft.text
    return .none
  }

  func handleUpdateSession(state: inout State, sessionID: String?) -> Effect<Action> {
    guard state.sessionID != sessionID else { return .none }

    state.sessionID = sessionID
    state.messages = []
    state.pendingMessageIDs = []
    state.unsupportedPartKinds = []
    state.canLoadMoreMessages = false
    state.isLoadingMoreMessages = false
    state.errorMessage = nil
    state.rebuildDerivedState()

    guard let sessionID, let serverURL = state.serverURL else {
      return .none
    }

    state.isLoading = true
    return loadMessagesEffect(sessionID: sessionID, serverURL: serverURL)
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
      return .send(.updateSession(sessionID))

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

  func handleSessionsFailed(state: inout State, error: String) -> Effect<Action> {
    state.isLoadingSessions = false
    state.errorMessage = error
    return .none
  }

  func handleNewSession(state: inout State) -> Effect<Action> {
    guard let serverURL = state.serverURL else {
      state.errorMessage = "Waiting for workspace connection..."
      return .none
    }

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

  func handleSessionCreationFailed(state: inout State, error: String) -> Effect<Action> {
    state.isLoading = false
    state.errorMessage = error
    return .none
  }

  func loadMessagesEffect(sessionID: String, serverURL: URL) -> Effect<Action> {
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
        await send(.messagesLoaded(messages))
      } catch {
        await send(.messagesFailed(error.localizedDescription))
      }
    }
  }

  func handleMessageLifecycleActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .messagesLoaded(messages):
      state.messages = messages
      state.isLoading = false
      state.errorMessage = nil
      state.rebuildDerivedState()
      return .none

    case let .messagesFailed(error):
      state.isLoading = false
      state.isLoadingMoreMessages = false
      state.errorMessage = error
      return .none

    case let .messageReceived(message):
      state.messages.append(message)
      state.isAssistantTyping = false
      state.rebuildDerivedState()
      return .none

    case let .messageSendCompleted(messageID):
      state.pendingMessageIDs.remove(messageID)
      state.rebuildDerivedState()
      return .none

    case let .messageSendFailed(messageID, error):
      state.pendingMessageIDs.remove(messageID)
      state.errorMessage = error
      state.rebuildDerivedState()
      return .none

    case let .loadMoreCompleted(messages, hasMore):
      state.messages.insert(contentsOf: messages, at: 0)
      state.canLoadMoreMessages = hasMore
      state.isLoadingMoreMessages = false
      state.rebuildDerivedState()
      return .none

    case let .loadMoreFailed(error):
      state.isLoadingMoreMessages = false
      state.errorMessage = error
      return .none

    default:
      return .none
    }
  }

  func handleLoadMore(state: inout State) -> Effect<Action> {
    guard !state.isLoadingMoreMessages,
          let sessionID = state.sessionID,
          let serverURL = state.serverURL else {
      return .none
    }

    state.isLoadingMoreMessages = true

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

  func handleMediaPickerPresented(state: inout State, isPresented: Bool) -> Effect<Action> {
    state.mediaPicker.isPresented = isPresented
    return .none
  }

  func handleMediaPickerAttachmentsUpdated(state: inout State, count: Int) -> Effect<Action> {
    state.mediaPicker.selectedAttachmentCount = count
    state.draft.attachmentCount = count
    return .none
  }
}
