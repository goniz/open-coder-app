import ComposableArchitecture
import DependencyClients
import Dependencies
import ExyteChat
import Foundation
import Models

package enum ChatUnsupportedMessagePartKind: String, Hashable, Sendable {
  case file
  case agent
  case tool
}

package struct ChatDraftState: Equatable {
  package var id: String?
  package var text: String
  package var attachmentCount: Int
  package var hasUnsupportedAttachments: Bool

  package init(
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

  package var trimmedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  package var isEmpty: Bool {
    trimmedText.isEmpty && attachmentCount == 0
  }
}

package struct ChatMediaPickerState: Equatable {
  package var isPresented = false
  package var selectedAttachmentCount = 0
}

@Reducer
package struct ChatFeature {
  @ObservableState
  package struct State: Equatable {
    package var messages: [OpenCodeMessage] = []
    package var exyteMessages: [Message] = []
    package var unsupportedPartKinds: Set<ChatUnsupportedMessagePartKind> = []
    package var currentMessage = ""
    package var isLoading = false
    package var isLoadingMoreMessages = false
    package var canLoadMoreMessages = false
    package var isAssistantTyping = false
    package var errorMessage: String?
    package var sessionID: String?
    package var serverURL: URL?
    package var sessions: [OpenCodeSession] = []
    package var isLoadingSessions = false
    package var pendingMessageIDs: Set<String> = []
    package var draft = ChatDraftState()
    package var mediaPicker = ChatMediaPickerState()
    package var currentSessionTitle: String {
      guard let sessionID = sessionID,
            let session = sessions.first(where: { $0.id == sessionID }) else {
        return "Select Session"
      }
      return session.displayTitle
    }

    package init(sessionID: String? = nil, serverURL: URL? = nil) {
      self.sessionID = sessionID
      self.serverURL = serverURL
    }
  }

  package enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case task
    case sendMessage
    case sendDraft(ChatDraftState)
    case draftUpdated(ChatDraftState)
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

  package init() {}

  package var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .binding, .messageMenuAction:
      return .none

    case .task:
      return handleTask(state: &state)

    case .sendMessage:
      return handleSendMessage(state: &state)

    case let .sendDraft(draft):
      return handleSendDraft(state: &state, draft: draft)

    case let .draftUpdated(draft):
      return handleDraftUpdated(state: &state, draft: draft)

    case let .updateSession(sessionID):
      return handleUpdateSession(state: &state, sessionID: sessionID)

    case .fetchSessions, .sessionsLoaded, .sessionsFailed, .selectSession,
         .newSession, .sessionCreated, .sessionCreationFailed:
      return handleSessionActions(state: &state, action: action)

    case .messagesLoaded, .messagesFailed, .messageReceived, .messageSendCompleted,
         .messageSendFailed, .loadMoreCompleted, .loadMoreFailed:
      return handleMessageLifecycleActions(state: &state, action: action)

    case .loadMore:
      return handleLoadMore(state: &state)

    case .mediaPickerPresented, .mediaPickerAttachmentsUpdated:
      return handleMediaPickerActions(state: &state, action: action)
    }
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
}
