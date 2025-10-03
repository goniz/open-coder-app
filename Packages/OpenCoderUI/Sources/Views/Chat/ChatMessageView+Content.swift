import SwiftUI
import ExyteChat
import OpenCoderCore

// MARK: - Message Part Extension for Enhanced Parts

extension MessagePart {
  init(from enhancedPart: EnhancedMessagePart) {
    switch enhancedPart {
    case .text(let content):
      self = .text(content)
    case .reasoning(let content):
      self = .text(content)
    case .file(let path, let content, _):
      self = .file(path: path, content: content)
    case .tool(let toolInfo):
      self = .tool(name: toolInfo.name, input: toolInfo.input ?? "", output: toolInfo.output ?? "")
    case .stepStart(let text, _):
      self = .text(text)
    case .stepFinish(let text, _, _):
      self = .text(text)
    case .snapshot(let text, _):
      self = .text(text)
    case .patch(let text, _, _):
      self = .text(text)
    case .agent(let content, _):
      self = .text(content)
    }
  }
}
