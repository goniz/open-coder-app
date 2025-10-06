import Foundation
@testable import Protocols
import XCTest

final class OpenCodeMessageTests: XCTestCase {
  func testDisplayModelNameWithGPT4() {
    let message = OpenCodeMessage(
      id: "test-id",
      sessionID: "test-session",
      parts: [.text("Hello", id: nil)],
      timestamp: Date(),
      role: .assistant,
      modelID: "gpt-4o",
      providerID: "openai"
    )
    
    XCTAssertEqual(message.displayModelName, "4O")
  }
  
  func testDisplayModelNameWithClaude() {
    let message = OpenCodeMessage(
      id: "test-id",
      sessionID: "test-session",
      parts: [.text("Hello", id: nil)],
      timestamp: Date(),
      role: .assistant,
      modelID: "claude-3-5-sonnet",
      providerID: "anthropic"
    )
    
    XCTAssertEqual(message.displayModelName, "3-5-SONNET")
  }
  
  func testDisplayModelNameWithNoModelID() {
    let message = OpenCodeMessage(
      id: "test-id",
      sessionID: "test-session", 
      parts: [.text("Hello", id: nil)],
      timestamp: Date(),
      role: .assistant,
      modelID: nil,
      providerID: nil
    )
    
    XCTAssertEqual(message.displayModelName, "Assistant")
  }
  
  func testDisplayModelNameWithUserMessage() {
    let message = OpenCodeMessage(
      id: "test-id",
      sessionID: "test-session",
      parts: [.text("Hello", id: nil)],
      timestamp: Date(),
      role: .user,
      modelID: nil,
      providerID: nil
    )
    
    XCTAssertEqual(message.displayModelName, "Assistant")
  }
}