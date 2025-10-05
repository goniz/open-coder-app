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
public struct ChatFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var messages: [OpenCodeMessage] = []
    public var exyteMessages: [Message] = []
    public var enhancedMessageParts: [String: [EnhancedMessagePart]] = [:] // messageID -> enhanced parts
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
    public var thinkingBlocksEnabled = true
    public var workspaceDisplayTitle: String?
    public var isEventsConnected = false
    public var shouldReconnectEvents = false

    public init(thinkingBlocksEnabled: Bool = true, workspaceDisplayTitle: String? = nil) {
      self.thinkingBlocksEnabled = thinkingBlocksEnabled
      self.workspaceDisplayTitle = workspaceDisplayTitle
    }
    public var currentSessionTitle: String {
      guard let sessionID = sessionID,
            let session = sessions.first(where: { $0.id == sessionID }) else {
        return "Select Session"
      }
      return session.displayTitle
    }

    public init(sessionID: String? = nil, serverURL: URL? = nil, workspaceDisplayTitle: String? = nil) {
      self.sessionID = sessionID
      self.serverURL = serverURL
      self.workspaceDisplayTitle = workspaceDisplayTitle
    }
  }

  public enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case task
    case sendMessage
    case sendDraft(ChatDraftState)
    case draftUpdated(ChatDraftState)
    case serverURLUpdated(URL?)
    case workspaceDisplayTitleUpdated(String?)
    case messagesLoaded([OpenCodeMessage])
    case messagesFailed(String)
    case messageReceived(OpenCodeMessage)
case messageUpdated(OpenCodeMessage)
case messagePartUpdated(sessionID: String, messageID: String, partID: String, part: MessagePart)
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
    case eventReceived(OpenCodeEvent)
    case eventsConnected
    case eventsDisconnected
    case reconnectEvents
    case appDidBecomeActive
    case appWillResignActive
  }

  @Dependency(\.openCodeAPIFactory) var openCodeAPIFactory
  @Dependency(\.openCodeConfiguration) var openCodeConfiguration

  public init() {
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce(core)
  }

  public func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .binding, .messageMenuAction:
      return .none
    case let .serverURLUpdated(url):
      return handleServerURLUpdated(state: &state, url: url)
    case let .workspaceDisplayTitleUpdated(title):
      state.workspaceDisplayTitle = title
      return .none
    case .task:
      return handleTask(state: &state)
    case .sendMessage, .sendDraft, .draftUpdated:
      return handleMessageDraftActions(state: &state, action: action)
    case .messagesLoaded, .messagesFailed, .messageReceived,
         .messageSendCompleted, .messageSendFailed, .loadMoreCompleted, .loadMoreFailed, .updateSession:
      return handleCoreMessageActions(state: &state, action: action)
    case .fetchSessions, .sessionsLoaded, .sessionsFailed, .selectSession,
         .newSession, .sessionCreated, .sessionCreationFailed:
      return handleSessionActions(state: &state, action: action)
    case .loadMore:
      return handleLoadMore(state: &state)
    case .mediaPickerPresented, .mediaPickerAttachmentsUpdated:
      return handleMediaPickerActions(state: &state, action: action)
    case .eventsConnected, .eventsDisconnected, .eventReceived, .reconnectEvents,
         .appDidBecomeActive, .appWillResignActive:
      return handleEventActions(state: &state, action: action)
    }
  }

  private func handleEventActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .eventsConnected:
      state.isEventsConnected = true
      state.shouldReconnectEvents = true
      return .none
    case .eventsDisconnected:
      state.isEventsConnected = false
      if state.shouldReconnectEvents && state.serverURL != nil {
        return .send(.reconnectEvents)
      }
      return .none
    case let .eventReceived(event):
      return handleEventReceived(state: &state, event: event)
    case .reconnectEvents:
      guard let serverURL = state.serverURL else {
        return .none
      }
      let factory = self.openCodeAPIFactory
      return subscribeToEventsEffect(serverURL: serverURL, factory: factory)
    case .appDidBecomeActive:
      if !state.isEventsConnected && state.shouldReconnectEvents && state.serverURL != nil {
        return .send(.reconnectEvents)
      }
      return .none
    case .appWillResignActive:
      return .none
    default:
      return .none
    }
  }

  private func handleEventReceived(state: inout State, event: OpenCodeEvent) -> Effect<Action> {
    switch event {
    case let .sessionUpdated(session):
      if let index = state.sessions.firstIndex(where: { $0.id == session.id }) {
        state.sessions[index] = session
      }
      return .none
    case let .sessionDeleted(sessionID):
      state.sessions.removeAll { $0.id == sessionID }
      if state.sessionID == sessionID {
        state.sessionID = nil
      }
      return .none
    case let .messageReceived(message):
      return .send(.messageReceived(message))
    case let .messageUpdated(message):
      return .send(.messageUpdated(message))
    case let .messagePartUpdated(sessionID, messageID, partID, part):
      return .send(.messagePartUpdated(sessionID: sessionID, messageID: messageID, partID: partID, part: part))
    case .unknown:
      return .none
    }
  }
}
