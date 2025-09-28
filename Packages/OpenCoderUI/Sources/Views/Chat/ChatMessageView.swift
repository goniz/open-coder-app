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

  var body: some View {
    VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 4) {
      if let reply = message.replyMessage {
        // Reply preview
        HStack {
          Text(reply.text.prefix(50) + (reply.text.count > 50 ? "..." : ""))
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
      }

      HStack {
        if !message.user.isCurrentUser {
          // Avatar placeholder for assistant
          Image(systemName: "person.circle.fill")
            .foregroundColor(.secondary)
            .frame(width: 32, height: 32)
        }

        VStack(alignment: .leading, spacing: 4) {
          if let status = message.status {
            switch status {
            case .sending:
              HStack(spacing: 4) {
                ForEach(0..<3) { index in
                  Circle().fill(Color.gray.opacity(0.5)).frame(width: 4)
                    .animation(
                      .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2),
                      value: status
                    )
                }
              }
            case .sent, .read:
              Image(systemName: "checkmark")
                .foregroundColor(.secondary)
                .opacity(message.user.isCurrentUser ? 1 : 0)
            case .error:
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            @unknown default:
              EmptyView()
            }
          }

          HStack {
            if !message.attachments.isEmpty {
              ForEach(message.attachments) { attachment in
                AttachmentView(attachment: attachment, onTap: { showAttachmentClosure(attachment) })
              }
            }

            Text(message.text)
              .padding(12)
              .background(
                message.user.isCurrentUser
                  ? AppColorType.green.color.opacity(0.8)
                  : Color(.systemGray5)
              )
              .foregroundColor(
                message.user.isCurrentUser ? .white : .primary
              )
              .cornerRadius(18)
              .frame(maxWidth: 280)
              .frame(alignment: message.user.isCurrentUser ? .trailing : .leading)
          }

          Text(message.createdAt, style: .time)
            .font(.caption2)
            .foregroundColor(.secondary)
        }

        if message.user.isCurrentUser {
          // Status for user messages
          Spacer()
        }
      }
    }
    .contextMenu {
      Button("Reply") { messageActionClosure(message, .reply) }
      Button("Copy") { UIPasteboard.general.string = message.text }
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
