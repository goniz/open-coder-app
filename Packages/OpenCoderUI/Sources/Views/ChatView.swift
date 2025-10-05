import ComposableArchitecture
import OpenCoderCore
import ExyteChat
import SwiftUI
import UIKit

struct ChatView: View {
  @Bindable var store: StoreOf<ChatFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if store.workspaceDisplayTitle != nil {
        HStack(spacing: 8) {
          Text(store.currentSessionTitle)
            .font(.title2)
            .fontWeight(.bold)
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 0)
          connectionStatusIndicators
          sessionSelectorButton
        }
        .padding(.horizontal, 12)
      }

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
    }
    .overlay(alignment: .topTrailing) {
      if store.isLoading {
        ProgressView()
          .padding()
      }
    }
    .task(id: store.sessionID) {
      await store.send(.task).finish()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      store.send(.appDidBecomeActive)
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
      store.send(.appWillResignActive)
    }
  }

  private var connectionStatusIndicators: some View {
    HStack(spacing: 6) {
      Image(systemName: store.serverURL != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(store.serverURL != nil ? .green : .red)
        .font(.caption)

      Image(systemName: store.isEventsConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(store.isEventsConnected ? .green : .red)
        .font(.caption)
    }
  }

  private var sessionSelectorButton: some View {
    HStack(spacing: 4) {
      if store.isLoadingSessions {
        ProgressView()
          .scaleEffect(0.8)
      }
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
        Image(systemName: "chevron.down.circle")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      .disabled(store.sessions.isEmpty && !store.isLoadingSessions)
    }
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
    ExyteChat.ChatView(
      messages: store.exyteMessages,
      chatType: .conversation,
      replyMode: .quote,
      didSendMessage: { draft in
        let mappedDraft = ChatDraftMapper.makeStateDraft(from: draft)
        store.send(.draftUpdated(mappedDraft))
        store.send(.sendDraft(mappedDraft))
      },
      reactionDelegate: nil,
      // swiftlint:disable:next line_length
      messageBuilder: { message, positionInUserGroup, positionInMessagesSection, positionInCommentsGroup, showContextMenuClosure, messageActionClosure, showAttachmentClosure in
        // Get enhanced parts for this message if available
        let enhancedParts = getEnhancedParts(for: message.id)

        return ChatMessageView(
          message: message,
          positionInUserGroup: positionInUserGroup,
          positionInMessagesSection: positionInMessagesSection,
          positionInCommentsGroup: positionInCommentsGroup,
          showContextMenuClosure: showContextMenuClosure,
          messageActionClosure: messageActionClosure,
          showAttachmentClosure: showAttachmentClosure,
          enhancedParts: enhancedParts,
          thinkingBlocksEnabled: store.thinkingBlocksEnabled
        )
      },
      inputViewBuilder: { textBinding, _, _, _, inputViewActionClosure, _ in
        HStack(spacing: 8) {
          TextField("Type a message...", text: textBinding, axis: .vertical)
            .textFieldStyle(.roundedBorder)

          if textBinding.wrappedValue.isEmpty {
            Button {
              inputViewActionClosure(.photo)
            } label: {
              Image(systemName: "photo")
                .foregroundColor(.secondary)
            }
          }

          Button {
            inputViewActionClosure(.send)
          } label: {
            Image(systemName: "paperplane.fill")
              .foregroundColor(sendButtonColor(isEmpty: textBinding.wrappedValue.isEmpty))
          }
          .disabled(textBinding.wrappedValue.isEmpty)
        }
        .padding(.horizontal)
        .background(Color(.systemGray6))
        .cornerRadius(20)
        .padding(.horizontal)
      },
      // swiftlint:disable:next line_length
      messageMenuAction: { (action: DefaultMessageMenuAction, defaultActionClosure: (ExyteChat.Message, DefaultMessageMenuAction) -> Void, message: ExyteChat.Message) in
        switch action {
        case .copy:
          defaultActionClosure(message, action)
        case .reply:
          store.send(.messageMenuAction(action, messageID: message.id))
        case .edit:
          defaultActionClosure(message, action)
        }
      },
      localization: ChatLocalization(
        inputPlaceholder: "Type a message...",
        signatureText: "",
        cancelButtonText: "Cancel",
        recentToggleText: "Recents",
        waitingForNetwork: "Waiting for network",
        recordingText: "Recording...",
        replyToText: "Reply to"
      )
    )
    .betweenListAndInputViewBuilder {
      if store.isAssistantTyping {
        return AnyView(
          HStack(spacing: 6) {
            ForEach(0..<3) { index in
              Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
                .opacity(0.6 - (Double(index) * 0.1))
            }
          }
          .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: store.isAssistantTyping)
          .padding()
        )
      } else {
        return AnyView(EmptyView())
      }
    }
    .enableLoadMore(pageSize: 10) { _ in
      await MainActor.run {
        if store.canLoadMoreMessages && !store.isLoadingMoreMessages {
          store.send(.loadMore)
        }
      }
    }
    .showNetworkConnectionProblem(store.errorMessage != nil)
    .chatTheme(
      {
        var colors = ChatTheme.Colors()
        colors.mainBG = Color.clear
        colors.mainTint = Color.primary
        colors.inputBG = Color(.systemGray6)
        colors.inputText = Color.primary
        colors.inputPlaceholderText = Color.secondary
        colors.messageMyBG = AppColorType.green.color.opacity(0.8)
        colors.messageMyText = Color.white
        colors.messageFriendBG = Color(.systemGray5)
        colors.messageFriendText = Color.primary
        colors.messageMyTimeText = Color.secondary
        colors.messageFriendTimeText = Color.secondary
        colors.sendButtonBackground = AppColorType.green.color
        colors.statusGray = Color.secondary
        return ChatTheme(colors: colors)
      }()
    )
    .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity, alignment: Alignment.top)
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

  private func sendButtonColor(isEmpty: Bool) -> Color {
    if isEmpty {
      return .secondary
    }
    return AppColorType.green.color
  }

  private func getEnhancedParts(for messageID: String) -> [EnhancedMessagePart]? {
    return store.enhancedMessageParts[messageID]
  }
}
