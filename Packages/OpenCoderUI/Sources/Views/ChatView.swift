import ComposableArchitecture
  import OpenCoderCore
  import ExyteChat
  import SwiftUI

struct ChatView: View {
  @Bindable var store: StoreOf<ChatFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      sessionSelector

      if store.sessionID == nil {
        sessionPlaceholder
      }

      chatSurface
        .padding(.horizontal, 12)

      if let unsupportedDescription = unsupportedMessageDescription {
        Text(unsupportedDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 12)
      }

      if let errorMessage = store.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(Color.red)
          .padding(.horizontal, 12)
      }
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

  private var sessionSelector: some View {
    HStack {
      Menu {
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
  }

  private var sessionPlaceholder: some View {
    Group {
      if store.serverURL == nil {
        Text("Waiting for workspace connection...")
      } else if store.sessions.isEmpty && !store.isLoadingSessions {
        Text("No sessions available. Create a new session to start chatting...")
      } else {
        Text("Select a session to start chatting...")
      }
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
  }
}

private extension ChatView {
  var chatSurface: some View {
    ExyteChat.ChatView(messages: store.exyteMessages) { draft in
      let mappedDraft = ChatDraftMapper.makeStateDraft(from: draft)
      store.send(.draftUpdated(mappedDraft))
      store.send(.sendDraft(mappedDraft))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  var unsupportedMessageDescription: String? {
    let kinds = store.unsupportedPartKinds
    guard !kinds.isEmpty else { return nil }
    let description = kinds
      .sorted { $0.rawValue < $1.rawValue }
      .map { $0.rawValue.capitalized }
      .joined(separator: ", ")
    return "Unsupported message content: \(description)."
  }
}
