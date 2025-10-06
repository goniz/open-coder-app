import XCTest
import ComposableArchitecture
@testable import OpenCoderUI
import Models

@MainActor
final class ChatFeatureStreamingTests: XCTestCase {
  func testMessagePartUpdatedEventUpdatesMessageAndDerivedState() async {
    var initialState = ChatFeature.State()
    initialState.sessionID = "session-123"
    let originalMessage = OpenCodeMessage(
      id: "message-abc",
      sessionID: "session-123",
      parts: [.text("initial", id: "part-1")],
      timestamp: Date(timeIntervalSince1970: 1),
      role: .assistant,
      modelID: "gpt-4o",
      providerID: "openai"
    )
    initialState.messages = [originalMessage]
    initialState.rebuildDerivedState()

    let store = TestStore(
      initialState: initialState,
      reducer: {
        ChatFeature()
      },
      withDependencies: {
        $0.date.now = { Date(timeIntervalSince1970: 42) }
      }
    )

    let updatedPart = MessagePart.text("stream chunk", id: "part-1")

    await store.send(
      .eventReceived(
        .messagePartUpdated(
          sessionID: "session-123",
          messageID: "message-abc",
          partID: "part-1",
          part: updatedPart
        )
      )
    )

    await store.receive(
      .messagePartUpdated(
        sessionID: "session-123",
        messageID: "message-abc",
        partID: "part-1",
        part: updatedPart
      )
    ) { state in
      state.messages[0] = OpenCodeMessage(
        id: "message-abc",
        sessionID: "session-123",
        parts: [.text("stream chunk", id: "part-1")],
        timestamp: Date(timeIntervalSince1970: 1),
        role: .assistant,
        modelID: "gpt-4o",
        providerID: "openai"
      )
      state.rebuildDerivedState()
    }

    XCTAssertEqual(store.state.exyteMessages.first?.text, "stream chunk")
  }

  func testMessagePartUpdatedEventInsertsPlaceholderWhenMessageMissing() async {
    var initialState = ChatFeature.State()
    initialState.sessionID = "session-xyz"

    let store = TestStore(
      initialState: initialState,
      reducer: {
        ChatFeature()
      },
      withDependencies: {
        $0.date.now = { Date(timeIntervalSince1970: 99) }
      }
    )

    let updatedPart = MessagePart.text("first chunk", id: "part-new")

    await store.send(
      .eventReceived(
        .messagePartUpdated(
          sessionID: "session-xyz",
          messageID: "message-new",
          partID: "part-new",
          part: updatedPart
        )
      )
    )

    await store.receive(
      .messagePartUpdated(
        sessionID: "session-xyz",
        messageID: "message-new",
        partID: "part-new",
        part: updatedPart
      )
    ) { state in
      let placeholder = OpenCodeMessage(
        id: "message-new",
        sessionID: "session-xyz",
        parts: [.text("first chunk", id: "part-new")],
        timestamp: Date(timeIntervalSince1970: 99),
        role: .assistant
      )
      state.messages = [placeholder]
      state.rebuildDerivedState()
    }

    XCTAssertEqual(store.state.messages.first?.parts.first, .text("first chunk", id: "part-new"))
    XCTAssertEqual(store.state.exyteMessages.first?.text, "first chunk")
  }
}
