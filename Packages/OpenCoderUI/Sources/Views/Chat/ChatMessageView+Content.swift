import SwiftUI
import ExyteChat
import OpenCoderCore

// MARK: - Message Part Extension for Enhanced Parts

extension MessagePart {
  var id: String? {
    switch self {
    case .text(_, let id),
         .reasoning(_, let id),
         .file(_, _, let id),
         .agent(_, _, let id),
         .tool(_, _, _, _, let id),
         .patch(_, _, let id),
         .stepStart(let id),
         .stepFinish(_, _, _, let id),
         .snapshot(_, let id):
      return id
    }
  }

  init(from enhancedPart: EnhancedMessagePart) {
    switch enhancedPart {
    case .text(let content):
      self = .text(content, id: nil)
    case .reasoning(let content):
      self = .text(content, id: nil)
    case .file(let path, let content, _):
      self = .file(path: path, content: content, id: nil)
    case .tool(let toolInfo):
      self = .tool(
        name: toolInfo.name,
        input: toolInfo.input ?? "",
        output: toolInfo.output ?? "",
        error: toolInfo.error,
        id: nil
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
