import SwiftUI
import UIKit
import ExyteChat
import OpenCoderCore

struct ChatMessageView: View {
  let message: Message
  let positionInUserGroup: PositionInUserGroup
  let positionInMessagesSection: PositionInMessagesSection
  let positionInCommentsGroup: CommentsPosition?
  let showContextMenuClosure: () -> Void
  let messageActionClosure: (Message, DefaultMessageMenuAction) -> Void
  let showAttachmentClosure: (Attachment) -> Void

  // Enhanced parts support
  let enhancedParts: [EnhancedMessagePart]?

  public init(
    message: Message,
    positionInUserGroup: PositionInUserGroup,
    positionInMessagesSection: PositionInMessagesSection,
    positionInCommentsGroup: CommentsPosition?,
    showContextMenuClosure: @escaping () -> Void,
    messageActionClosure: @escaping (Message, DefaultMessageMenuAction) -> Void,
    showAttachmentClosure: @escaping (Attachment) -> Void,
    enhancedParts: [EnhancedMessagePart]? = nil
  ) {
    self.message = message
    self.positionInUserGroup = positionInUserGroup
    self.positionInMessagesSection = positionInMessagesSection
    self.positionInCommentsGroup = positionInCommentsGroup
    self.showContextMenuClosure = showContextMenuClosure
    self.messageActionClosure = messageActionClosure
    self.showAttachmentClosure = showAttachmentClosure
    self.enhancedParts = enhancedParts
  }

  var body: some View {
    let hasContent = hasVisibleContent()
    let showLabel = shouldShowLabel()
    
    if hasContent {
      VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 2) {
        if showLabel {
          Text(message.user.isCurrentUser ? "You" : message.user.name)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.leading, message.user.isCurrentUser ? 0 : 8)
            .padding(.trailing, message.user.isCurrentUser ? 8 : 0)
            .padding(.top, 8)
        }

      VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 4) {
        if let reply = message.replyMessage {
          Text(reply.text.prefix(50) + (reply.text.count > 50 ? "..." : ""))
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }

        if let enhancedParts = enhancedParts, !enhancedParts.isEmpty {
          ChatMessageViewContent(
            message: message,
            enhancedParts: enhancedParts
          )
        } else if !message.text.isEmpty {
          if message.user.isCurrentUser {
            Text(message.text)
              .padding(12)
              .background(AppColorType.green.color.opacity(0.8))
              .foregroundColor(.white)
              .cornerRadius(18)
          } else {
            Text(message.text)
              .foregroundColor(.primary)
          }
        }

        if !message.attachments.isEmpty {
          ForEach(message.attachments) { attachment in
            AttachmentView(attachment: attachment) { showAttachmentClosure(attachment) }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: message.user.isCurrentUser ? .trailing : .leading)
      .padding(.leading, message.user.isCurrentUser ? 60 : 8)
      .padding(.trailing, message.user.isCurrentUser ? 8 : 8)

      if shouldShowTimestamp() {
        HStack(spacing: 4) {
          Text(message.createdAt, style: .time)
            .font(.caption2)
            .foregroundColor(.secondary)

          if let status = message.status {
            switch status {
            case .sending:
              HStack(spacing: 2) {
                ForEach(0..<3) { index in
                  Circle().fill(Color.gray.opacity(0.5)).frame(width: 3, height: 3)
                    .animation(
                      .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2),
                      value: status
                    )
                }
              }
            case .sent, .read:
              Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(message.user.isCurrentUser ? 1 : 0)
            case .error:
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.red)
            @unknown default:
              EmptyView()
            }
          }
        }
        .padding(.leading, message.user.isCurrentUser ? 60 : 8)
        .padding(.trailing, message.user.isCurrentUser ? 8 : 8)
        .padding(.bottom, 4)
      }
      }
      .contextMenu {
        Button("Reply") { messageActionClosure(message, .reply) }
        Button("Copy") { UIPasteboard.general.string = message.text }
      }
    }
  }
  
  private func hasVisibleContent() -> Bool {
    if !message.text.isEmpty {
      return true
    }
    if let enhancedParts = enhancedParts, !enhancedParts.isEmpty {
      return true
    }
    if !message.attachments.isEmpty {
      return true
    }
    return false
  }
  
  private func shouldShowLabel() -> Bool {
    return positionInUserGroup == .first || positionInUserGroup == .single
  }
  
  private func shouldShowTimestamp() -> Bool {
    return positionInUserGroup == .last || positionInUserGroup == .single
  }
}

struct ChatMessageViewContent: View {
  let message: Message
  let enhancedParts: [EnhancedMessagePart]

  var body: some View {
    let renderer = CompositeMessageRenderer()
    if message.user.isCurrentUser {
      renderer.render(parts: enhancedParts, message: message)
        .padding(12)
        .background(AppColorType.green.color.opacity(0.8))
        .foregroundColor(.white)
        .cornerRadius(18)
    } else {
      renderer.render(parts: enhancedParts, message: message)
        .foregroundColor(.primary)
    }
  }
}

struct AttachmentView: View {
  let attachment: Attachment
  let onTap: () -> Void

  var body: some View {
    if attachment.type == .image {
      AsyncImage(url: attachment.thumbnail) { image in
        image.resizable().aspectRatio(contentMode: .fit)
      } placeholder: {
        ProgressView()
      }
      .frame(maxWidth: 200, maxHeight: 200)
      .cornerRadius(12)
      .onTapGesture(perform: onTap)
    } else if attachment.type == .video {
      VStack {
        Image(systemName: "video.fill")
          .foregroundColor(.white)
          .frame(width: 50, height: 50)
          .background(Color.blue)
          .clipShape(Circle())
        Text("Video")
          .font(.caption)
      }
      .frame(width: 100, height: 100)
      .background(Color.gray.opacity(0.2))
      .cornerRadius(12)
      .onTapGesture(perform: onTap)
    }
  }
}
