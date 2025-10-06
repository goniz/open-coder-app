import XCTest
@testable import Implementations

final class SSEEventParserTests: XCTestCase {
  func testParsesSingleEventFromSingleChunk() {
    var parser = SSEEventParser()
    var events: [String] = []

    parser.ingest("data: {\"type\":\"ping\"}\n\n") { events.append($0) }
    parser.finish { events.append($0) }

    XCTAssertEqual(events, ["{\"type\":\"ping\"}"])
  }

  func testParsesEventSplitAcrossChunks() {
    var parser = SSEEventParser()
    var events: [String] = []

    parser.ingest("data: {\"type\":\"session.updated\"") { events.append($0) }
    parser.ingest(",\"data\":1}\n\n") { events.append($0) }
    parser.finish { events.append($0) }

    XCTAssertEqual(events, ["{\"type\":\"session.updated\",\"data\":1}"])
  }

  func testParsesMultipleEventsWithMixedChunkBoundaries() {
    var parser = SSEEventParser()
    var events: [String] = []

    parser.ingest("data: {\"id\":1}\n\n") { events.append($0) }
    parser.ingest("data: {\"id\":2}\n\n") { events.append($0) }
    parser.finish { events.append($0) }

    XCTAssertEqual(
      events,
      ["{\"id\":1}", "{\"id\":2}"]
    )
  }
}
