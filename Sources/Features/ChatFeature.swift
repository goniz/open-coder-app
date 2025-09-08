import ComposableArchitecture
import Foundation

@Reducer
package struct ChatFeature {
  @ObservableState
  package struct State: Equatable {
    package var messages: [Message] = []
    package var currentMessage = ""
    package var isLoading = false

    package init() {}
  }

  package enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case task
    case sendMessage
    case messageSent(Message)
    case receiveMessage(Message)
  }

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
      state.isLoading = true
      return .run { send in
        await send(.binding(.set(\.isLoading, false)))
      }

    case .sendMessage:
      guard !state.currentMessage.isEmpty else { return .none }
      let message = Message(content: state.currentMessage, isFromUser: true)
      state.messages.append(message)
      state.currentMessage = ""
      return .run { send in
        await send(.messageSent(message))
      }

    case .messageSent:
      return .none

    case let .receiveMessage(message):
      state.messages.append(message)
      return .none
    }
  }
}

package struct Message: Equatable, Identifiable {
  package let id = UUID()
  package let content: String
  package let isFromUser: Bool
  package let timestamp = Date()
}
