import XCTest
@testable import OpenCoderCore

final class FileMentionBuilderTests: XCTestCase {
  func testMergedText_DoesNotDuplicateExistingPathMention() {
    let file = AttachedFile(path: "Sources/App/App.swift", content: nil)
    let text = "Please review @Sources/App/App.swift today"

    let merged = FileMentionBuilder.mergedText(text, with: [file])
    XCTAssertEqual(merged, text, "Should not prepend a second @path token")
  }

  func testMergedText_PrependsMissingMention() {
    let file = AttachedFile(path: "README.md", content: nil)
    let text = "Check this out"

    let merged = FileMentionBuilder.mergedText(text, with: [file])
    XCTAssertEqual(merged, "@README.md \(text)")
  }

  func testNextToken_PrefersPathMentionWhenPresent() {
    let file = AttachedFile(path: "Assets/icon.png", content: nil, metadata: ["mimeType": "image/png"])
    let text = "Look at @Assets/icon.png please"

    let match = FileMentionBuilder.nextToken(in: text, for: file, startFrom: 0)
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.token, "@Assets/icon.png")

    if let match {
      let start = text.index(text.startIndex, offsetBy: match.start)
      let end = text.index(text.startIndex, offsetBy: match.end)
      XCTAssertEqual(String(text[start..<end]), "@Assets/icon.png")
    }
  }

  func testNextToken_FallsBackToDisplayName_WhenPathMissing() {
    // For images, display name becomes "[Image]"
    let image = AttachedFile(path: "Assets/screenshot.png", content: nil, metadata: ["mimeType": "image/png"])
    let text = "Here is an [Image] for context"

    let match = FileMentionBuilder.nextToken(in: text, for: image, startFrom: 0)
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.token, "[Image]")
  }
}
