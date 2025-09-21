import ComposableArchitecture
import DependencyClients
import Dependencies
import Foundation
import Models

@Reducer
package struct ChatFeature {
  @ObservableState
  package struct State: Equatable {
    package var messages: [OpenCodeMessage] = []
    package var currentMessage = ""
    package var isLoading = false
    package var errorMessage: String?
    package var sessionID: String?
    package var serverURL: URL?

    package init(sessionID: String? = nil, serverURL: URL? = nil) {
      self.sessionID = sessionID
      self.serverURL = serverURL
    }
  }

  package enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case task
    case sendMessage
    case messagesLoaded([OpenCodeMessage])
    case messagesFailed(String)
    case messageReceived(OpenCodeMessage)
    case messageSendFailed(String)
    case updateSession(String?)
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
    case .binding:
      return .none

    case .task:
      return handleTask(state: &state)

    case .sendMessage:
      return handleSendMessage(state: &state)

    case let .messagesLoaded(messages):
      return handleMessagesLoaded(state: &state, messages: messages)

    case let .messagesFailed(errorMessage):
      return handleMessagesFailed(state: &state, errorMessage: errorMessage)

    case let .messageReceived(message):
      return handleMessageReceived(state: &state, message: message)

    case let .messageSendFailed(errorMessage):
      return handleMessageSendFailed(state: &state, errorMessage: errorMessage)

    case let .updateSession(sessionID):
      return handleUpdateSession(state: &state, sessionID: sessionID)
    }
  }

  private func loadMessagesEffect(sessionID: String, serverURL: URL) -> Effect<Action> {
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

private extension ChatFeature {
  func handleTask(state: inout State) -> Effect<Action> {
    guard let sessionID = state.sessionID,
      let serverURL = state.serverURL else { return .none }
    state.isLoading = true
    state.errorMessage = nil
    return loadMessagesEffect(sessionID: sessionID, serverURL: serverURL)
  }

  func handleSendMessage(state: inout State) -> Effect<Action> {
    guard let sessionID = state.sessionID,
      let serverURL = state.serverURL,
      !state.currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return .none
    }

    let content = state.currentMessage
    state.currentMessage = ""
    state.isLoading = true
    state.errorMessage = nil

    let userMessage = OpenCodeMessage(
      id: UUID().uuidString,
      sessionID: sessionID,
      parts: [.text(content)],
      timestamp: Date(),
      role: .user
    )
    state.messages.append(userMessage)

    let baseConfiguration = openCodeConfiguration
    let configuration = OpenCodeConfiguration(
      serverURL: serverURL,
      timeout: baseConfiguration.timeout,
      retryCount: baseConfiguration.retryCount
    )
    let apiClient = openCodeAPIFactory.make(configuration)

    return .run { send in
      do {
        let response = try await apiClient.sendMessage(
          sessionID: sessionID,
          parts: [.text(content)]
        )
        await send(.messageReceived(response))
      } catch {
        await send(.messageSendFailed(error.localizedDescription))
      }
    }
  }

  func handleMessagesLoaded(state: inout State, messages: [OpenCodeMessage]) -> Effect<Action> {
    state.messages = messages
    state.isLoading = false
    state.errorMessage = nil
    return .none
  }

  func handleMessagesFailed(state: inout State, errorMessage: String) -> Effect<Action> {
    state.isLoading = false
    state.errorMessage = errorMessage
    return .none
  }

  func handleMessageReceived(state: inout State, message: OpenCodeMessage) -> Effect<Action> {
    state.messages.append(message)
    state.isLoading = false
    return .none
  }

  func handleMessageSendFailed(state: inout State, errorMessage: String) -> Effect<Action> {
    state.isLoading = false
    state.errorMessage = errorMessage
    return .none
  }

  func handleUpdateSession(state: inout State, sessionID: String?) -> Effect<Action> {
    guard state.sessionID != sessionID else { return .none }
    state.sessionID = sessionID
    state.messages = []
    state.errorMessage = nil

    guard let sessionID, let serverURL = state.serverURL else { return .none }
    state.isLoading = true
    return loadMessagesEffect(sessionID: sessionID, serverURL: serverURL)
  }
}
