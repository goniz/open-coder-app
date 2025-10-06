import XCTest
@testable import Implementations
import Models

final class OpenCodeAPIClientLiveEventParsingTests: XCTestCase {
  private let client = LiveOpenCodeAPIClient(
    configuration: .development
  )

  func testParseMessagePartUpdatedReturnsEvent() {
    let eventPayload = """
    {"type":"message.part.updated","properties":{"part":{"id":"part-123","type":"text","content":"stream chunk","sessionID":"session-456","messageID":"message-789"}}}
    """

    let event = client.parseEvent(from: eventPayload)

    guard case let .messagePartUpdated(sessionID, messageID, partID, part)? = event else {
      return XCTFail("Expected message.part.updated event, got \(String(describing: event))")
    }

    XCTAssertEqual(sessionID, "session-456")
    XCTAssertEqual(messageID, "message-789")
    XCTAssertEqual(partID, "part-123")
    XCTAssertEqual(part, .text("stream chunk", id: "part-123"))
  }
}
