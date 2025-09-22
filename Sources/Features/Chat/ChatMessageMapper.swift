import DependencyClients
import ExyteChat
import Foundation

enum ChatMessageMapper {
  static func buildMessages(
    from messages: [OpenCodeMessage],
    pendingMessageIDs: Set<String>
  ) -> (messages: [Message], unsupportedParts: Set<ChatUnsupportedMessagePartKind>) {
    messages.reduce(
      into: (
        messages: [Message](),
        unsupportedParts: Set<ChatUnsupportedMessagePartKind>()
      )
    ) { result, message in
      let mapped = map(message: message, isPending: pendingMessageIDs.contains(message.id))
      result.messages.append(mapped.message)
      result.unsupportedParts.formUnion(mapped.unsupportedParts)
    }
  }

  private static func map(
    message: OpenCodeMessage,
    isPending: Bool
  ) -> (message: Message, unsupportedParts: Set<ChatUnsupportedMessagePartKind>) {
    let content = textAndUnsupportedParts(from: message.parts)
    let user = user(for: message.role)
    let status = status(for: message.role, isPending: isPending)
    let exyteMessage = Message(
      id: message.id,
      user: user,
      status: status,
      createdAt: message.timestamp,
      text: content.text
    )
    return (exyteMessage, content.unsupportedParts)
  }

  private static func textAndUnsupportedParts(
    from parts: [MessagePart]
  ) -> (text: String, unsupportedParts: Set<ChatUnsupportedMessagePartKind>) {
    var textSegments: [String] = []
    var unsupported: Set<ChatUnsupportedMessagePartKind> = []

    for part in parts {
      switch part {
      case let .text(content):
        textSegments.append(content)
      case .file:
        unsupported.insert(.file)
      case .agent:
        unsupported.insert(.agent)
      case .tool:
        unsupported.insert(.tool)
      }
    }

    return (textSegments.joined(separator: "\n"), unsupported)
  }

  private static func user(for role: MessageRole) -> User {
    switch role {
    case .user:
      User(id: "user", name: "You", avatarURL: nil, isCurrentUser: true)
    case .assistant:
      User(id: "assistant", name: "Assistant", avatarURL: nil, isCurrentUser: false)
    case .system:
      User(id: "system", name: "System", avatarURL: nil, type: .system)
    }
  }

  private static func status(for role: MessageRole, isPending: Bool) -> Message.Status? {
    switch role {
    case .user:
      return isPending ? .sending : .sent
    case .assistant:
      return .read
    case .system:
      return nil
    }
  }
}

extension ChatFeature.State {
  mutating func rebuildDerivedState() {
    let result = ChatMessageMapper.buildMessages(
      from: messages,
      pendingMessageIDs: pendingMessageIDs
    )
    exyteMessages = result.messages
    unsupportedPartKinds = result.unsupportedParts
  }
}
