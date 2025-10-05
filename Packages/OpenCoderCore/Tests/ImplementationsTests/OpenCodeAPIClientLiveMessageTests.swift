import XCTest
import OpenAPIGenerated
import OpenAPIRuntime
@testable import Implementations
@testable import Models
@testable import Protocols

final class OpenCodeAPIClientLiveMessageTests: XCTestCase {
  
  // MARK: - Message Info Extraction Tests
  
  func testExtractMessageInfoFromUserMessage() {
    let client = createTestClient()
    
    let userMessage = Components.Schemas.UserMessage(
      id: "user-123",
      time: Components.Schemas.UserMessage.timePayload(created: 1234567890000)
    )
    
    let message = Components.Schemas.Message(value1: userMessage, value2: nil, value3: nil)
    let info = client.extractMessageInfoAndTimestamp(message)
    
    XCTAssertEqual(info.id, "user-123")
    XCTAssertEqual(info.role, .user)
    XCTAssertEqual(info.timestamp.timeIntervalSince1970, 1234567890.0, accuracy: 0.01)
    XCTAssertNil(info.modelID)
    XCTAssertNil(info.providerID)
  }
  
  func testExtractMessageInfoFromAssistantMessage() {
    let client = createTestClient()
    
    let assistantMessage = Components.Schemas.AssistantMessage(
      id: "assistant-123",
      time: Components.Schemas.AssistantMessage.timePayload(created: 1234567890000),
      modelID: "gpt-4",
      providerID: "openai"
    )
    
    let message = Components.Schemas.Message(value1: nil, value2: assistantMessage, value3: nil)
    let info = client.extractMessageInfoAndTimestamp(message)
    
    XCTAssertEqual(info.id, "assistant-123")
    XCTAssertEqual(info.role, .assistant)
    XCTAssertEqual(info.timestamp.timeIntervalSince1970, 1234567890.0, accuracy: 0.01)
    XCTAssertEqual(info.modelID, "gpt-4")
    XCTAssertEqual(info.providerID, "openai")
  }
  
  func testExtractMessageInfoFallback() {
    let client = createTestClient()
    
    let message = Components.Schemas.Message(value1: nil, value2: nil, value3: nil)
    let info = client.extractMessageInfoAndTimestamp(message)
    
    XCTAssertNotNil(info.id) // Should generate UUID
    XCTAssertEqual(info.role, .assistant)
    XCTAssertNil(info.modelID)
    XCTAssertNil(info.providerID)
  }
  
  // MARK: - Message Parts Parsing Tests
  
  func testParseTextPart() {
    let client = createTestClient()
    
    let textPart = Components.Schemas.TextPart(
      id: nil,
      _type: .text,
      text: "Hello, world!",
      synthetic: nil,
      time: nil
    )
    
    let part = Components.Schemas.Part(
      value1: textPart, value2: nil, value3: nil, value4: nil,
      value5: nil, value6: nil, value7: nil, value8: nil, value9: nil
    )
    
    let parts = client.parseMessageParts([part])
    
    XCTAssertEqual(parts.count, 1)
    if case .text(let content) = parts.first {
      XCTAssertEqual(content, "Hello, world!")
    } else {
      XCTFail("Expected text part")
    }
  }
  
  func testParseReasoningPart() {
    let client = createTestClient()
    
    let reasoningPart = Components.Schemas.ReasoningPart(
      id: nil,
      _type: .reasoning,
      text: "Let me think...",
      time: nil
    )
    
    let part = Components.Schemas.Part(
      value1: nil, value2: reasoningPart, value3: nil, value4: nil,
      value5: nil, value6: nil, value7: nil, value8: nil, value9: nil
    )
    
    let parts = client.parseMessageParts([part])
    
    XCTAssertEqual(parts.count, 1)
    if case .reasoning(let content) = parts.first {
      XCTAssertEqual(content, "Let me think...")
    } else {
      XCTFail("Expected reasoning part")
    }
  }
  
  func testParseFilePart() {
    let client = createTestClient()
    
    let filePart = Components.Schemas.FilePart(
      id: nil,
      _type: .file,
      filename: "test.txt",
      url: "file content here",
      time: nil
    )
    
    let part = Components.Schemas.Part(
      value1: nil, value2: nil, value3: filePart, value4: nil,
      value5: nil, value6: nil, value7: nil, value8: nil, value9: nil
    )
    
    let parts = client.parseMessageParts([part])
    
    XCTAssertEqual(parts.count, 1)
    if case .file(let path, let content) = parts.first {
      XCTAssertEqual(path, "test.txt")
      XCTAssertEqual(content, "file content here")
    } else {
      XCTFail("Expected file part")
    }
  }
  
  func testParseToolPartCompleted() {
    let client = createTestClient()
    
    let completedState = Components.Schemas.ToolPart.statePayload.Value3Payload(
      input: OpenAPIRuntime.OpenAPIValueContainer(["param": "value"]),
      output: "Tool completed successfully"
    )
    
    let toolState = Components.Schemas.ToolPart.statePayload(
      value1: nil, value2: nil, value3: completedState, value4: nil
    )
    
    let toolPart = Components.Schemas.ToolPart(
      id: nil,
      _type: .tool,
      tool: "test-tool",
      state: toolState,
      time: nil
    )
    
    let part = Components.Schemas.Part(
      value1: nil, value2: nil, value3: nil, value4: toolPart,
      value5: nil, value6: nil, value7: nil, value8: nil, value9: nil
    )
    
    let parts = client.parseMessageParts([part])
    
    XCTAssertEqual(parts.count, 1)
    if case .tool(let name, let input, let output, let error) = parts.first {
      XCTAssertEqual(name, "test-tool")
      XCTAssertFalse(input.isEmpty)
      XCTAssertEqual(output, "Tool completed successfully")
      XCTAssertNil(error)
    } else {
      XCTFail("Expected tool part")
    }
  }
  
  func testParseToolPartError() {
    let client = createTestClient()
    
    let errorState = Components.Schemas.ToolPart.statePayload.Value4Payload(
      input: Components.Schemas.ToolPart.statePayload.Value4Payload.inputPayload(
        additionalProperties: ["param": OpenAPIRuntime.OpenAPIValueContainer("value")]
      ),
      error: "Tool execution failed"
    )
    
    let toolState = Components.Schemas.ToolPart.statePayload(
      value1: nil, value2: nil, value3: nil, value4: errorState
    )
    
    let toolPart = Components.Schemas.ToolPart(
      id: nil,
      _type: .tool,
      tool: "failing-tool",
      state: toolState,
      time: nil
    )
    
    let part = Components.Schemas.Part(
      value1: nil, value2: nil, value3: nil, value4: toolPart,
      value5: nil, value6: nil, value7: nil, value8: nil, value9: nil
    )
    
    let parts = client.parseMessageParts([part])
    
    XCTAssertEqual(parts.count, 1)
    if case .tool(let name, let input, let output, let error) = parts.first {
      XCTAssertEqual(name, "failing-tool")
      XCTAssertFalse(input.isEmpty)
      XCTAssertTrue(output.isEmpty)
      XCTAssertEqual(error, "Tool execution failed")
    } else {
      XCTFail("Expected tool part with error")
    }
  }
  
  func testParsePatchPart() {
    let client = createTestClient()
    
    let patchPart = Components.Schemas.PatchPart(
      id: nil,
      _type: .patch,
      hash: "abc123",
      files: ["file1.txt", "file2.txt"],
      time: nil
    )
    
    let part = Components.Schemas.Part(
      value1: nil, value2: nil, value3: nil, value4: nil,
      value5: nil, value6: nil, value7: nil, value8: patchPart, value9: nil
    )
    
    let parts = client.parseMessageParts([part])
    
    XCTAssertEqual(parts.count, 1)
    if case .patch(let hash, let files) = parts.first {
      XCTAssertEqual(hash, "abc123")
      XCTAssertEqual(files, ["file1.txt", "file2.txt"])
    } else {
      XCTFail("Expected patch part")
    }
  }
  
  func testParseAgentPart() {
    let client = createTestClient()
    
    let agentPart = Components.Schemas.AgentPart(
      id: nil,
      _type: .agent,
      name: "test-agent",
      source: OpenAPIRuntime.OpenAPIValueContainer("Agent result content"),
      time: nil
    )
    
    let part = Components.Schemas.Part(
      value1: nil, value2: nil, value3: nil, value4: nil,
      value5: nil, value6: nil, value7: nil, value8: nil, value9: agentPart
    )
    
    let parts = client.parseMessageParts([part])
    
    XCTAssertEqual(parts.count, 1)
    if case .agent(let type, let result) = parts.first {
      XCTAssertEqual(type, "test-agent")
      XCTAssertEqual(result, "Agent result content")
    } else {
      XCTFail("Expected agent part")
    }
  }
  
  // MARK: - Message Data Source Tests
  
  func testParseMessageDataFromPromptResponse() {
    let client = createTestClient()
    
    let assistantMessage = Components.Schemas.AssistantMessage(
      id: "msg-123",
      time: Components.Schemas.AssistantMessage.timePayload(created: 1234567890000),
      modelID: "gpt-4",
      providerID: "openai"
    )
    
    let textPart = Components.Schemas.TextPart(
      id: nil,
      _type: .text,
      text: "Hello!",
      synthetic: nil,
      time: nil
    )
    
    let part = Components.Schemas.Part(
      value1: textPart, value2: nil, value3: nil, value4: nil,
      value5: nil, value6: nil, value7: nil, value8: nil, value9: nil
    )
    
    let source = TestableOpenCodeAPIClient.MessageDataSource.promptResponse(
      Operations.session_period_prompt.Output.Ok.Body.jsonPayload(
        info: assistantMessage,
        parts: [part]
      )
    )
    
    let message = client.parseMessageData(from: source, sessionID: "session-123")
    
    XCTAssertNotNil(message)
    XCTAssertEqual(message?.id, "msg-123")
    XCTAssertEqual(message?.sessionID, "session-123")
    XCTAssertEqual(message?.role, .assistant)
    XCTAssertEqual(message?.modelID, "gpt-4")
    XCTAssertEqual(message?.providerID, "openai")
    XCTAssertEqual(message?.parts.count, 1)
    
    if case .text(let content) = message?.parts.first {
      XCTAssertEqual(content, "Hello!")
    } else {
      XCTFail("Expected text part")
    }
  }
  
  // MARK: - Helper Methods
  
  private func createTestClient() -> TestableOpenCodeAPIClient {
    let config = OpenCodeConfiguration.development
    return TestableOpenCodeAPIClient(configuration: config)
  }
}

// MARK: - Testable Client

private class TestableOpenCodeAPIClient: LiveOpenCodeAPIClient {
  
  // Expose private methods and types for testing
  func extractMessageInfoAndTimestamp(_ messageInfo: Components.Schemas.Message) -> MessageInfo {
    super.extractMessageInfoAndTimestamp(messageInfo)
  }
  
  func parseMessageParts(_ parts: [Components.Schemas.Part]) -> [MessagePart] {
    super.parseMessageParts(parts)
  }
  
  func parseMessageData(from source: MessageDataSource, sessionID: String) -> OpenCodeMessage? {
    super.parseMessageData(from: source, sessionID: sessionID)
  }
  
  // Expose the enum for testing
  typealias MessageDataSource = LiveOpenCodeAPIClient.MessageDataSource
  typealias MessageInfo = LiveOpenCodeAPIClient.MessageInfo
}