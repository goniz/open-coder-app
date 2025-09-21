import ComposableArchitecture
import DependencyClients
import Features
import SwiftUI

struct ChatView: View {
  @Bindable var store: StoreOf<ChatFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Session selection dropdown
      HStack {
        Menu {
          // New Session button as first item
          Button {
            store.send(.newSession)
          } label: {
            HStack {
              Image(systemName: "plus")
              Text("New Session")
            }
          }

          if !store.sessions.isEmpty {
            Divider()

            ForEach(store.sessions) { session in
              Button(session.displayTitle) {
                store.send(.selectSession(session.id))
              }
            }
          }

          if store.sessions.isEmpty && !store.isLoadingSessions {
            Text("No sessions available")
              .foregroundStyle(.secondary)
          }
        } label: {
          HStack(spacing: 8) {
            Text(store.currentSessionTitle)
              .font(.title2)
              .fontWeight(.bold)
              .lineLimit(1)
            Image(systemName: "chevron.down")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
          .frame(width: 350)
        }
        .disabled(store.sessions.isEmpty && !store.isLoadingSessions)

        Spacer()

        if store.isLoadingSessions {
          ProgressView()
            .scaleEffect(0.8)
        }
      }
      .padding(.horizontal, 12)

      if store.sessionID == nil {
        if store.serverURL == nil {
          Text("Waiting for workspace connection...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        } else if store.sessions.isEmpty && !store.isLoadingSessions {
          Text("No sessions available. Create a new session to start chatting...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        } else {
          Text("Select a session to start chatting...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        }
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
    .task {
      await store.send(.fetchSessions).finish()
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
