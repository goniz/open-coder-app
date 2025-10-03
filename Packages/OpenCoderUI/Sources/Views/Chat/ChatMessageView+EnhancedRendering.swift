import SwiftUI
import OpenCoderCore
import ExyteChat

// MARK: - Composite Message Renderer

public struct CompositeMessageRenderer {
  private let renderers: [AnyMessagePartRenderer]

  public init(renderers: [AnyMessagePartRenderer] = Self.defaultRenderers) {
    self.renderers = renderers
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
    VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 8) {
      ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
        renderPart(part, message: message)
          .frame(maxWidth: .infinity, alignment: message.user.isCurrentUser ? .trailing : .leading)
      }
    }
  }

  private func renderPart(_ part: EnhancedMessagePart, message: Message) -> AnyView {
    for renderer in renderers where renderer.canRender(part) {
      return renderer.render(part, message: message)
    }
    return AnyView(EmptyView())
  }
}
