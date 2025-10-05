import SwiftUI
import OpenCoderCore
import ExyteChat

// MARK: - Composite Message Renderer

public struct CompositeMessageRenderer {
  private let renderers: [AnyMessagePartRenderer]
  private let thinkingBlocksEnabled: Bool

  public init(renderers: [AnyMessagePartRenderer] = Self.defaultRenderers, thinkingBlocksEnabled: Bool = true) {
    self.renderers = renderers
    self.thinkingBlocksEnabled = thinkingBlocksEnabled
  }

  public static var defaultRenderers: [AnyMessagePartRenderer] {
    [
      AnyMessagePartRenderer(TextPartRenderer()),
      AnyMessagePartRenderer(ReasoningPartRenderer()),
      AnyMessagePartRenderer(FilePartRenderer()),
      AnyMessagePartRenderer(ToolPartRenderer()),
      AnyMessagePartRenderer(StepPartRenderer()),
      AnyMessagePartRenderer(PatchPartRenderer()),
      AnyMessagePartRenderer(AgentPartRenderer())
    ]
  }

  public func render(parts: [EnhancedMessagePart], message: Message) -> some View {
    let visibleParts = parts.filter { part in
      if case .reasoning = part, !thinkingBlocksEnabled {
        return false
      }
      return true
    }

    return VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 8) {
      ForEach(Array(visibleParts.enumerated()), id: \.offset) { _, part in
        renderPart(part, message: message)
          .frame(maxWidth: .infinity, alignment: message.user.isCurrentUser ? .trailing : .leading)
      }
    }
  }

  private func renderPart(_ part: EnhancedMessagePart, message: Message) -> AnyView {
    for renderer in renderers where renderer.canRender(part) {
      return renderer.render(part, message: message)
    }
    return AnyView(
      Text("Unsupported message part")
        .font(.caption)
        .foregroundColor(.orange)
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    )
  }
}
