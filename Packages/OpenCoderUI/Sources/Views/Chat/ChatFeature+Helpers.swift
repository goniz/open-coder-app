import ComposableArchitecture
import Foundation
import Protocols
import ExyteChat
import Models
import OpenAPIGenerated

package actor SharedAPIClientCache {
  static let shared = SharedAPIClientCache()

  private var clients: [URL: OpenCodeAPIClientProtocol] = [:]

  private init() {}

  func client(for serverURL: URL, factory: OpenCodeAPIClientFactoryProtocol) -> OpenCodeAPIClientProtocol {
    if let cachedClient = clients[serverURL] {
      return cachedClient
    }

    let configuration = OpenCodeConfiguration(serverURL: serverURL)
    let client = factory.make(configuration)
    clients[serverURL] = client
    return client
  }

  func removeClient(for serverURL: URL) {
    clients.removeValue(forKey: serverURL)
  }

  func clearCache() {
    clients.removeAll()
  }
}

extension ChatFeature {

  // MARK: - File Attachment & Suggestions

  func handleFileAttachmentActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .showFileSuggestions(query):
      return handleShowFileSuggestions(state: &state, query: query)
    case let .fileSuggestionsLoaded(suggestions):
      return handleFileSuggestionsLoaded(state: &state, suggestions: suggestions)
    case let .fileSuggestionsFailed(error):
      return handleFileSuggestionsFailed(state: &state, error: error)
    case let .selectFileSuggestion(suggestion):
      return handleSelectFileSuggestion(state: &state, suggestion: suggestion)
    case let .attachFile(file):
      return handleAttachFile(state: &state, file: file)
    case let .removeAttachedFile(id):
      return handleRemoveAttachedFile(state: &state, id: id)
    case let .fileContentLoaded(path, content):
      return handleFileContentLoaded(state: &state, path: path, content: content)
    case let .fileContentFailed(path, error):
      return handleFileContentFailed(state: &state, path: path, error: error)
    default:
      return .none
    }
  }

  private func handleShowFileSuggestions(state: inout State, query: String) -> Effect<Action> {
    state.draft.suggestionQuery = query
    state.draft.isShowingSuggestions = true
    guard let serverURL = state.serverURL else {
      state.draft.suggestions = makeInlineSuggestions(from: query)
      return .none
    }
    let factory = self.openCodeAPIFactory
    return .run { send in
      do {
        let api = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let results = try await api.findFiles(query: query, directory: nil)
        await send(.fileSuggestionsLoaded(results))
      } catch {
        await send(.fileSuggestionsFailed(error.localizedDescription))
      }
    }
  }

  private func handleFileSuggestionsLoaded(state: inout State, suggestions: [FileSuggestion]) -> Effect<Action> {
    state.draft.suggestions = suggestions
    state.draft.isShowingSuggestions = true
    return .none
  }

  private func handleFileSuggestionsFailed(state: inout State, error: String) -> Effect<Action> {
    state.errorMessage = error
    state.draft.isShowingSuggestions = false
    return .none
  }

  private func handleSelectFileSuggestion(state: inout State, suggestion: FileSuggestion) -> Effect<Action> {
    let file = AttachedFile(path: suggestion.path, content: nil)
    state.draft.attachedFiles.append(file)
    state.draft.isShowingSuggestions = false

    guard let serverURL = state.serverURL else { return .none }
    let filePath = suggestion.path
    let factory = self.openCodeAPIFactory
    return .run { send in
      do {
        let api = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let content = try await api.readFile(path: filePath, directory: nil)
        await send(.fileContentLoaded(path: filePath, content: content))
      } catch {
        await send(.fileContentFailed(path: filePath, error: error.localizedDescription))
      }
    }
  }

  private func handleAttachFile(state: inout State, file: AttachedFile) -> Effect<Action> {
    state.draft.attachedFiles.append(file)
    return .none
  }

  private func handleRemoveAttachedFile(state: inout State, id: UUID) -> Effect<Action> {
    state.draft.attachedFiles.removeAll { $0.id == id }
    return .none
  }

  private func handleFileContentLoaded(state: inout State, path: String, content: String) -> Effect<Action> {
    if let index = state.draft.attachedFiles.firstIndex(where: { $0.path == path }) {
      let data = content.data(using: .utf8)
      let existing = state.draft.attachedFiles[index]
      state.draft.attachedFiles[index] = AttachedFile(
        path: existing.path,
        content: data,
        metadata: existing.metadata
      )
    }
    return .none
  }

  private func handleFileContentFailed(state: inout State, path: String, error: String) -> Effect<Action> {
    state.errorMessage = "Failed to load file content for \(path): \(error)"
    return .none
  }

  private func makeInlineSuggestions(from query: String) -> [FileSuggestion] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    // Provide a few plausible filename completions locally as a stopgap
    let base = (trimmed as NSString).lastPathComponent
    let candidates = [
      base,
      base + ".swift",
      base + ".md",
      base + ".txt",
      base + ".json"
    ]

    return candidates.map { name in
      let path: String
      if trimmed.contains("/") {
        // Continue the typed directory structure
        let dir = (trimmed as NSString).deletingLastPathComponent
        path = (dir as NSString).appendingPathComponent(name)
      } else {
        path = name
      }
      let ext = (name as NSString).pathExtension
      let type = ext.isEmpty ? nil : ext
      return FileSuggestion(path: path, name: name, type: type)
    }
  }

  func handleTask(state: inout State) -> Effect<Action> {
    guard let sessionID = state.sessionID,
          let serverURL = state.serverURL else {
      state.errorMessage = "Select a session to start chatting."
      return .none
    }

    state.isLoading = true
    state.errorMessage = nil
    let factory = self.openCodeAPIFactory
    return .merge(
      loadMessagesEffect(sessionID: sessionID, serverURL: serverURL, factory: factory),
      subscribeToEventsEffect(serverURL: serverURL, factory: factory),
      .send(.fetchProviders)
    )
  }

  func subscribeToEventsEffect(serverURL: URL, factory: OpenCodeAPIClientFactoryProtocol) -> Effect<Action> {
    return .run { send in
      let client = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)

      do {
        let stream = try await client.subscribeToEvents()
        await send(.eventsConnected)

        for try await event in stream {
          await send(.eventReceived(event))
        }

        await send(.eventsDisconnected)
      } catch {
        await send(.eventsDisconnected)
      }
    }
  }

  func handleSendMessage(state: inout State) -> Effect<Action> {
    handleSendDraft(state: &state, draft: state.draft)
  }

  func handleSendDraft(state: inout State, draft: ChatDraftState) -> Effect<Action> {
    guard let sessionID = state.sessionID,
          let serverURL = state.serverURL else {
      state.errorMessage = "Select a session before sending messages."
      return .none
    }

    let trimmedText = draft.trimmedText
    guard !trimmedText.isEmpty || !draft.attachedFiles.isEmpty else {
      return .none
    }

    let messageID = draft.id ?? UUID().uuidString

    // Build complete text with file references included
    let fullText = FileMentionBuilder.mergedText(trimmedText, with: draft.attachedFiles)

    // Create structured file parts using the new MessagePart case
    let (_, structuredParts) = createStructuredMessageParts(from: draft.attachedFiles, in: fullText)

    // Build parts array (as an immutable value to satisfy Sendable captures)
    let parts: [MessagePart] = {
      var tmp: [MessagePart] = []
      if !fullText.isEmpty {
        tmp.append(.text(fullText, id: nil))
      }
      tmp.append(contentsOf: structuredParts)
      return tmp
    }()

    let providerID = state.selectedProviderID
    let modelID = state.selectedModelID

    state.draft = ChatDraftState()
    state.isLoading = true

    let factory = self.openCodeAPIFactory
    return .run { send in
      do {
        let apiClient = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let serverMessage = try await apiClient.sendMessage(
          sessionID: sessionID,
          parts: parts,
          providerID: providerID,
          modelID: modelID
        )
        await send(.messageReceived(serverMessage))
        await send(.messageSendCompleted(messageID: serverMessage.id))
      } catch {
        await send(.messageSendFailed(messageID: messageID, error: error.localizedDescription))
      }
    }
  }

  func handleDraftUpdated(state: inout State, draft: ChatDraftState) -> Effect<Action> {
    state.draft = draft
    return .none
  }

  private func createStructuredMessageParts(
    from attachedFiles: [AttachedFile],
    in text: String
  ) -> ([AttachedFile], [MessagePart]) {
    var updatedFiles: [AttachedFile] = []
    var messageParts: [MessagePart] = []
    var currentPosition = 0

    for file in attachedFiles {
      // Prefer anchoring to an explicit path mention if present (e.g. "@full/path").
      // Otherwise, fall back to the display name (e.g. "[Image]") which may have been
      // synthesized by buildTextWithFileReferences.
      let match = FileMentionBuilder.nextToken(in: text, for: file, startFrom: currentPosition)
      let startIndex = match?.start ?? currentPosition
      let endIndex = match.map { $0.end } ?? startIndex + file.displayName.utf16.count
      let token = match?.token ?? file.displayName

      // Update search position for next file
      currentPosition = endIndex

      // Update file with positions
      var updatedFile = file
      updatedFile.startIndex = startIndex
      updatedFile.endIndex = endIndex
      updatedFiles.append(updatedFile)

      // Create URL based on file type
      let url: String
      if file.isImage, let content = file.content {
        let base64Content = content.base64EncodedString()
        url = "data:\(file.mimeType);base64,\(base64Content)"
      } else {
        // For text files, use file:// URL
        let absolutePath = file.path.hasPrefix("/")
          ? file.path
          : FileManager.default.currentDirectoryPath + "/" + file.path
        url = "file://\(absolutePath)"
      }

      // Create MessagePart.structuredFile (displayText must match the token found in text)
      let messagePart = MessagePart.structuredFile(
        path: file.path,
        url: url,
        mimeType: file.mimeType,
        displayText: token,
        startIndex: startIndex,
        endIndex: endIndex,
        id: file.id.uuidString
      )

      messageParts.append(messagePart)
    }

    return (updatedFiles, messageParts)
  }

  private func buildTextWithFileReferences(text: String, attachedFiles: [AttachedFile]) -> String {
    // If no files, return text unchanged
    guard !attachedFiles.isEmpty else { return text }

    // Only add references for files that are NOT already mentioned in the text.
    // A mention can appear either as the explicit path token ("@<path>") or as the
    // display name (e.g. "[Image]") in cases like images.
    var missingReferences: [String] = []
    for file in attachedFiles {
      let pathToken = file.displayPath          // "@<path>"
      let nameToken = file.displayName          // "@<path>" or "[Image]"

      // If either token already exists in the text, don't prepend another copy.
      if text.contains(pathToken) || text.contains(nameToken) {
        continue
      }

      // Otherwise, queue the display name to be inserted (keeps prior UX the same).
      missingReferences.append(nameToken)
    }

    // Nothing to add — return as-is.
    guard !missingReferences.isEmpty else { return text }

    let prefix = missingReferences.joined(separator: " ")
    return text.isEmpty ? prefix : "\(prefix) \(text)"
  }

  func handleUpdateSession(state: inout State, sessionID: String?) -> Effect<Action> {
    state.sessionID = sessionID
    state.messages = []
    state.exyteMessages = []
    state.unsupportedPartKinds = []
    state.errorMessage = nil
    state.messagesAwaitingDetails = []
    state.scrollToBottomSequence = 0
    state.scrollToBottomSequence = 0
    return .none
  }

  func handleSessionActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .fetchSessions:
      return handleFetchSessions(state: &state)
    case let .sessionsLoaded(sessions):
      return handleSessionsLoaded(state: &state, sessions: sessions)
    case let .sessionsFailed(error):
      return handleSessionsFailed(state: &state, error: error)
    case let .selectSession(sessionID):
      return handleSelectSession(state: &state, sessionID: sessionID)
    case .newSession:
      return handleNewSession(state: &state)
    case let .sessionCreated(session):
      return handleSessionCreated(state: &state, session: session)
    case let .sessionCreationFailed(error):
      return handleSessionCreationFailed(state: &state, error: error)
    default:
      return .none
    }
  }

  private func handleFetchSessions(state: inout State) -> Effect<Action> {
    guard let serverURL = state.serverURL else {
      return .run { send in
        await send(.sessionsFailed("No server URL configured"))
      }
    }

    state.isLoadingSessions = true
    let factory = self.openCodeAPIFactory
    return .run { send in
      do {
        let apiClient = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let sessions = try await apiClient.listSessions()
        await send(.sessionsLoaded(sessions))
      } catch {
        await send(.sessionsFailed(error.localizedDescription))
      }
    }
  }

  private func handleSessionsLoaded(state: inout State, sessions: [OpenCodeSession]) -> Effect<Action> {
    state.sessions = sessions
    state.isLoadingSessions = false
    return .none
  }

  private func handleSessionsFailed(state: inout State, error: String) -> Effect<Action> {
    state.errorMessage = error
    state.isLoadingSessions = false
    return .none
  }

  private func handleSelectSession(state: inout State, sessionID: String) -> Effect<Action> {
    state.sessionID = sessionID
    clearSessionState(state: &state)
    return .send(.task)
  }

  private func handleNewSession(state: inout State) -> Effect<Action> {
    guard let serverURL = state.serverURL else {
      return .run { send in
        await send(.sessionCreationFailed("No server URL configured"))
      }
    }

    state.isLoadingSessions = true
    let factory = self.openCodeAPIFactory
    return .run { send in
      do {
        let apiClient = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let session = try await apiClient.createSession()
        await send(.sessionCreated(session))
      } catch {
        await send(.sessionCreationFailed(error.localizedDescription))
      }
    }
  }

  private func handleSessionCreated(state: inout State, session: OpenCodeSession) -> Effect<Action> {
    state.sessions.append(session)
    state.sessionID = session.id
    state.isLoadingSessions = false
    clearSessionState(state: &state)
    return .none
  }

  private func handleSessionCreationFailed(state: inout State, error: String) -> Effect<Action> {
    state.isLoadingSessions = false
    state.errorMessage = error
    return .none
  }

  private func clearSessionState(state: inout State) {
    state.messages = []
    state.exyteMessages = []
    state.unsupportedPartKinds = []
    state.errorMessage = nil
    state.messagesAwaitingDetails = []
    state.scrollToBottomSequence = 0
  }

  func handleLoadMore(state: inout State) -> Effect<Action> {
    guard let sessionID = state.sessionID,
          let serverURL = state.serverURL,
          state.canLoadMoreMessages,
          !state.isLoadingMoreMessages else {
      return .none
    }

    state.isLoadingMoreMessages = true
    let factory = self.openCodeAPIFactory
    return loadMessagesEffect(sessionID: sessionID, serverURL: serverURL, factory: factory, isLoadMore: true)
  }

  func handleMediaPickerPresented(state: inout State, isPresented: Bool) -> Effect<Action> {
    state.mediaPicker.isPresented = isPresented
    return .none
  }

  func handleMediaPickerAttachmentsUpdated(state: inout State, count: Int) -> Effect<Action> {
    state.mediaPicker.selectedAttachmentCount = count
    return .none
  }

  func handleMediaPickerActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .mediaPickerPresented(isPresented):
      return handleMediaPickerPresented(state: &state, isPresented: isPresented)
    case let .mediaPickerAttachmentsUpdated(count):
      return handleMediaPickerAttachmentsUpdated(state: &state, count: count)
    default:
      return .none
    }
  }

  func handleCoreMessageActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .messagesLoaded, .messagesFailed, .messageReceived, .messageDetailsLoaded,
         .messageDetailsFailed, .messageUpdated, .messagePartUpdated:
      return handleMessageLifecycleActions(state: &state, action: action)
    case let .messageSendCompleted(messageID):
      return handleMessageSendCompleted(state: &state, messageID: messageID)
    case let .messageSendFailed(messageID, error):
      return handleMessageSendFailed(state: &state, messageID: messageID, error: error)
    case let .loadMoreCompleted(messages, hasMore):
      return handleLoadMoreCompleted(state: &state, messages: messages, hasMore: hasMore)
    case let .loadMoreFailed(error):
      return handleLoadMoreFailed(state: &state, error: error)
    case let .updateSession(sessionID):
      return handleUpdateSession(state: &state, sessionID: sessionID)
    default:
      return .none
    }
  }

  private func loadMessagesEffect(
    sessionID: String,
    serverURL: URL,
    factory: OpenCodeAPIClientFactoryProtocol,
    isLoadMore: Bool = false
  ) -> Effect<Action> {
    .run { send in
      do {
        let apiClient = await SharedAPIClientCache.shared.client(for: serverURL, factory: factory)
        let messages = try await apiClient.getMessages(sessionID: sessionID)
        if isLoadMore {
          await send(.loadMoreCompleted(messages, hasMore: false))
        } else {
          await send(.messagesLoaded(messages))
        }
      } catch {
        if isLoadMore {
          await send(.loadMoreFailed(error.localizedDescription))
        } else {
          await send(.messagesFailed(error.localizedDescription))
        }
      }
    }
  }

  func handleServerURLUpdated(state: inout State, url: URL?) -> Effect<Action> {
    let oldURL = state.serverURL
    state.serverURL = url
    state.messages = []
    state.exyteMessages = []
    state.unsupportedPartKinds = []
    state.errorMessage = nil
    state.messagesAwaitingDetails = []

    // Clear cached client for old URL if it changed
    if let oldURL = oldURL, oldURL != url {
      return .merge(
        .run { _ in
          await SharedAPIClientCache.shared.removeClient(for: oldURL)
        },
        url != nil ? .send(.fetchProviders) : .none
      )
    }

    return url != nil ? .send(.fetchProviders) : .none
  }

  func handleMessageDraftActions(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .sendMessage:
      return .send(.sendDraft(state.draft))
    case let .sendDraft(draft):
      return handleSendDraft(state: &state, draft: draft)
    case let .draftUpdated(draft):
      return handleDraftUpdated(state: &state, draft: draft)
    default:
      return .none
    }
  }
}
