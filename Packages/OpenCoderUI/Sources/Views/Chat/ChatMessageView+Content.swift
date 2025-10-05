import SwiftUI
import ExyteChat
import OpenCoderCore

// MARK: - Message Part Extension for Enhanced Parts

extension MessagePart {
  init(from enhancedPart: EnhancedMessagePart) {
    switch enhancedPart {
    case .text(let content, _):
      self = .text(content)
    case .reasoning(let content, _):
      self = .text(content)
    case .file(let path, let content, _):
      self = .file(path: path, content: content)
    case .tool(let toolInfo):
      self = .tool(
        name: toolInfo.name,
        input: toolInfo.input ?? "",
        output: toolInfo.output ?? "",
        error: toolInfo.error
      )
    case .stepStart(let text, _):
      self = .text(text, id: nil)
    case .stepFinish(let text, _, _):
      self = .text(text, id: nil)
    case .snapshot(let text, _):
      self = .text(text, id: nil)
    case .patch(let text, _, _):
      self = .text(text, id: nil)
    case .agent(let content, _):
      self = .text(content, id: nil)
    }
  }
}
