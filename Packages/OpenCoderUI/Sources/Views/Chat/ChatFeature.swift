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
    case .binding, .messageMenuAction:
      return .none
    case let .serverURLUpdated(url):
      state.serverURL = url
      state.messages = []
      state.exyteMessages = []
      state.pendingMessageIDs = []
      state.unsupportedPartKinds = []
      state.errorMessage = nil
      return .none
    case .task:
      return handleTask(state: &state)
    case .sendMessage:
      return .send(.sendDraft(state.draft))
    case let .sendDraft(draft):
      return handleSendDraft(state: &state, draft: draft)
    case let .draftUpdated(draft):
      return handleDraftUpdated(state: &state, draft: draft)
    case .messagesLoaded, .messagesFailed, .messageReceived,
         .messageSendCompleted, .messageSendFailed, .loadMoreCompleted, .loadMoreFailed:
      return handleCoreMessageActions(state: &state, action: action)
    case .updateSession:
      return handleCoreMessageActions(state: &state, action: action)
    case .fetchSessions, .sessionsLoaded, .sessionsFailed, .selectSession,
         .newSession, .sessionCreated, .sessionCreationFailed:
      return handleSessionActions(state: &state, action: action)
    case .loadMore:
      return handleLoadMore(state: &state)
    case .mediaPickerPresented:
      return handleMediaPickerActions(state: &state, action: action)
    case .mediaPickerAttachmentsUpdated:
      return handleMediaPickerActions(state: &state, action: action)
    }
  }
}
