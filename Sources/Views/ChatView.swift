import ComposableArchitecture
import DependencyClients
import Features
import SwiftUI

struct ChatView: View {
  @Bindable var store: StoreOf<ChatFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if store.sessionID == nil {
        Text("Workspace session is initializing...")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(store.messages) { message in
            ChatBubble(message: message)
          }
        }
        .padding(.horizontal, 12)
      }

      if let errorMessage = store.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(Color.red)
          .padding(.horizontal, 12)
      }

      HStack(spacing: 8) {
        TextField("Type a message...", text: $store.currentMessage)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .disabled(store.sessionID == nil)

        Button("Send") {
          store.send(.sendMessage)
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.sessionID == nil || store.isLoading)
      }
      .padding(.horizontal, 12)
    }
    .overlay(alignment: .topTrailing) {
      if store.isLoading {
        ProgressView()
          .padding()
      }
    }
    .task {
      await store.send(.task).finish()
    }
  }
}

private struct ChatBubble: View {
  let message: OpenCodeMessage

  var body: some View {
    HStack {
      if message.role == .user {
        Spacer(minLength: 32)
        content
          .background(Color.blue.opacity(0.2))
          .foregroundStyle(.primary)
      } else {
        content
          .background(Color.gray.opacity(0.2))
          .foregroundStyle(.primary)
        Spacer(minLength: 32)
      }
    }
  }

  private var content: some View {
    Text(messageText())
      .frame(maxWidth: 280, alignment: .leading)
      .padding(8)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func messageText() -> String {
    message.parts.compactMap { part in
      if case let .text(content) = part {
        return content
      }
      return nil
    }
    .joined(separator: "\n")
  }
}
