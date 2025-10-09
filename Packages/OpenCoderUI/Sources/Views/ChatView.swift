import ComposableArchitecture
import OpenCoderCore
import ExyteChat
import SwiftUI
import UIKit

struct ChatView: View {
  @State private var isSettingsExpanded = false
  @State private var activeSettingsMenu: ActiveSettingsMenu?
  @State private var isAutoScrollEnabled = true
  @Bindable var store: StoreOf<ChatFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if store.workspaceDisplayTitle != nil {
        VStack(alignment: .leading, spacing: 12) {
          Text(store.currentSessionTitle)
            .font(.title2)
            .fontWeight(.bold)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

          settingsMenu
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
    .onChange(of: store.scrollToBottomSequence) { _, _ in
      guard isAutoScrollEnabled else { return }
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .onScrollToBottom, object: nil)
      }
    }
    .onChange(of: store.sessionID) { _, _ in
      isAutoScrollEnabled = true
    }
  }

  private var settingsMenu: some View {
    DisclosureGroup(isExpanded: $isSettingsExpanded) {
      VStack(alignment: .leading, spacing: 12) {
        sessionSelectorButton
        Divider()
        ModelPickerView(
          store: store,
          isExpanded: binding(for: .model)
        )
      }
      .padding(.top, 8)
    } label: {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "slider.horizontal.3")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 6) {
          Text("Chat Settings")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)

          Text(settingsSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)

          statusChips
            .padding(.top, 2)
        }

        Spacer(minLength: 4)

        Image(systemName: isSettingsExpanded ? "chevron.up" : "chevron.down")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
          .padding(.top, 2)
      }
      .padding(.vertical, 6)
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(.systemGray6))
      )
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .animation(.easeInOut(duration: 0.2), value: isSettingsExpanded)
    .onChange(of: isSettingsExpanded) { _, newValue in
      if !newValue {
        activeSettingsMenu = nil
      }
    }
  }

  private var settingsSummary: String {
    let providerText: String
    if let provider = store.currentProvider {
      if let model = store.currentModel {
        providerText = "\(provider.name) · \(model.displayName)"
      } else {
        providerText = provider.name
      }
    } else {
      providerText = "Select provider & model"
    }

    return providerText
  }

  private var statusChips: some View {
    HStack(spacing: 6) {
      statusChip(
        label: "SSH",
        isActive: store.serverURL != nil
      )

      statusChip(
        label: "OC",
        isActive: store.isEventsConnected
      )
    }
  }

  private func statusChip(label: String, isActive: Bool) -> some View {
    HStack(spacing: 3) {
      Image(systemName: isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(isActive ? Color.green : Color.red)
        .font(.system(size: 9))

      Text(label)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(Color(.systemGray5))
    .cornerRadius(5)
  }

  private var sessionSelectorButton: some View {
    SettingsDropdown(
      isExpanded: binding(for: .session),
      isDisabled: store.isLoadingSessions
    ) {
      SettingsPickerLabel(
        title: "Session",
        displayText: store.currentSessionTitle,
        isPlaceholder: store.sessionID == nil,
        isLoading: store.isLoadingSessions,
        iconName: "bubble.left.and.text.bubble.right.fill",
        isActive: activeSettingsMenu == .session
      )
    } content: { dismiss in
      SessionPickerMenuContent(store: store, dismiss: dismiss)
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
    .onTapGesture(perform: collapseSettings)
  }
}

private extension ChatView {
  func binding(for menu: ActiveSettingsMenu) -> Binding<Bool> {
    Binding(
      get: { activeSettingsMenu == menu },
      set: { newValue in
        withAnimation(.easeInOut(duration: 0.2)) {
          if newValue {
            activeSettingsMenu = menu
          } else if activeSettingsMenu == menu {
            activeSettingsMenu = nil
          }
        }
      }
    )
  }

  enum ActiveSettingsMenu {
    case session
    case model
  }

  func collapseSettings() {
    activeSettingsMenu = nil
  }

  struct SessionPickerMenuContent: View {
    @Bindable var store: StoreOf<ChatFeature>
    let dismiss: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Button {
          store.send(.newSession)
          dismiss()
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
              .foregroundStyle(Color.accentColor)
            Text("New Session")
              .foregroundStyle(.primary)
            Spacer(minLength: 0)
          }
          .padding(.vertical, 8)
          .padding(.horizontal, 10)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(Color(.systemGray6))
          )
        }
        .buttonStyle(.plain)

        if store.isLoadingSessions {
          HStack(spacing: 8) {
            ProgressView()
            Text("Loading sessions…")
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        } else if store.sessions.isEmpty {
          Text("No sessions available")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Divider()
          ScrollView {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(store.sessions) { session in
                let isSelected = store.sessionID == session.id
                Button {
                  store.send(.selectSession(session.id))
                  dismiss()
                } label: {
                  HStack {
                    Text(session.displayTitle)
                      .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Spacer(minLength: 0)
                    if isSelected {
                      Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                    }
                  }
                  .padding(.vertical, 8)
                  .padding(.horizontal, 10)
                  .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                      .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
                  )
                }
                .buttonStyle(.plain)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 260)
        }
      }
      .padding(.vertical, 16)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(.systemBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color(.systemGray4))
      )
    }
  }

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
        // Get identified parts for this message if available (stable IDs for streaming)
        let identifiedParts = getIdentifiedParts(for: message.id)

        return ChatMessageView(
          message: message,
          positionInUserGroup: positionInUserGroup,
          positionInMessagesSection: positionInMessagesSection,
          positionInCommentsGroup: positionInCommentsGroup,
          showContextMenuClosure: showContextMenuClosure,
          messageActionClosure: messageActionClosure,
          showAttachmentClosure: showAttachmentClosure,
          identifiedParts: identifiedParts,
          thinkingBlocksEnabled: store.thinkingBlocksEnabled
        )
      },
      inputViewBuilder: { textBinding, _, _, _, inputViewActionClosure, _ in
VStack(spacing: 6) {
          // Inline file suggestions panel (above the input)
          if store.draft.isShowingSuggestions && !store.draft.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(store.draft.suggestions) { suggestion in
                Button {
                  let newText = replaceLastAtToken(
                    in: textBinding.wrappedValue,
                    with: suggestion.path
                  )
                  textBinding.wrappedValue = newText
                  var draft = store.draft
                  draft.text = newText
                  store.send(.draftUpdated(draft))
                  store.send(.selectFileSuggestion(suggestion))
                } label: {
                  HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                      .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                      Text(suggestion.name)
                        .font(.caption)
                        .foregroundStyle(.primary)
                      Text(suggestion.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                  }
                  .padding(.horizontal, 8)
                  .padding(.vertical, 6)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
              }
            }
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator))
            )
            .padding(.horizontal)
            .frame(maxHeight: 120)
            .transition(.opacity)
          }

          VStack(alignment: .leading, spacing: 8) {
            if !store.draft.attachedFiles.isEmpty {
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                  ForEach(store.draft.attachedFiles) { file in
                    HStack(spacing: 4) {
                      Text(file.path.components(separatedBy: "/").last ?? file.path)
                        .font(.caption)
                      Button {
                        store.send(.removeAttachedFile(file.id))
                      } label: {
                        Image(systemName: "xmark.circle.fill")
                          .foregroundColor(.red)
                          .font(.caption)
                      }
                    }
                    .padding(6)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                  }
                }
              }
              .frame(height: 30)
            }

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
                UIApplication.shared.sendAction(
                  #selector(UIResponder.resignFirstResponder),
                  to: nil,
                  from: nil,
                  for: nil
                )
              } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                  .foregroundColor(.secondary)
              }

              Button {
                inputViewActionClosure(.send)
              } label: {
                Image(systemName: "paperplane.fill")
                  .foregroundColor(sendButtonColor(
                    isEmpty: textBinding.wrappedValue.isEmpty && store.draft.attachedFiles.isEmpty
                  ))
              }
              .disabled(textBinding.wrappedValue.isEmpty && store.draft.attachedFiles.isEmpty)
            }
          }
          .padding(.horizontal)
          .background(Color(.systemGray6))
          .cornerRadius(20)
          .padding(.horizontal)
          .onChange(of: textBinding.wrappedValue) { _, newValue in
            var draft = store.draft
            draft.text = newValue
            store.send(.draftUpdated(draft))
          }

          // Suggestions are rendered above; none here.
        }

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
    .onTapGesture(perform: collapseSettings)
    .overlay(alignment: .topLeading) {
      ChatScrollObserver(isAutoScrollEnabled: $isAutoScrollEnabled)
        .allowsHitTesting(false)
        .frame(width: 0, height: 0)
    }
    .onChange(of: store.draft.text) { _, newValue in
      if let lastAtIndex = newValue.lastIndex(of: "@") {
        let tail = String(newValue[newValue.index(after: lastAtIndex)...])
        let firstToken = tail.split(separator: " ").first
        let query = firstToken.map(String.init) ?? ""
        if !query.isEmpty {
          store.send(.showFileSuggestions(query))
        } else {
          store.draft.isShowingSuggestions = false
        }
      } else {
        store.draft.isShowingSuggestions = false
      }
    }
    // Inline suggestions replace the sheet presentation
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

  // Replace the last token that starts with '@' with the provided full path.
  private func replaceLastAtToken(in text: String, with replacement: String) -> String {
    guard let atIndex = text.lastIndex(of: "@") else { return text }
    let afterAt = text.index(after: atIndex)
    let tail = text[afterAt...]

    // Token ends at first whitespace; if none, replace until end
    if let end = tail.firstIndex(where: { $0.isWhitespace }) {
      let head = text[..<atIndex]
      let remainder = tail[end...]
      return String(head) + "@" + replacement + String(remainder)
    } else {
      let head = text[..<atIndex]
      return String(head) + "@" + replacement
    }
  }

  private func getIdentifiedParts(for messageID: String) -> [ChatMessageMapper.IdentifiedEnhancedPart]? {
    return store.identifiedEnhancedMessageParts[messageID]
  }
}
