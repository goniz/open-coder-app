import ComposableArchitecture
import Features
import SwiftUI

struct ChatView: View {
  @Bindable var store: StoreOf<ChatFeature>

  var body: some View {
    VStack {
      Text("Chat", bundle: Bundle.module)
      ScrollView {
        ForEach(store.messages) { message in
          HStack {
            if message.isFromUser {
              Spacer()
              Text(message.content)
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
            } else {
              Text(message.content)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
              Spacer()
            }
          }
        }
      }
      HStack {
        TextField("Type a message...", text: $store.currentMessage)
          .textFieldStyle(RoundedBorderTextFieldStyle())
        Button("Send") {
          store.send(.sendMessage)
        }
      }
      .padding()
    }
    .task {
      await store.send(.task).finish()
    }
  }
}
