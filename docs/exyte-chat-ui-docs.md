# Exyte Chat Library Documentation for iOS Development

## Executive Summary

You are a coding agent working with the Exyte Chat library - a comprehensive SwiftUI chat interface framework. This library provides a production-ready, customizable chat UI with built-in media support, requiring iOS 17+ and Xcode 15+.

**GitHub Repository**: https://github.com/exyte/Chat  
**Package Name**: ExyteChat  
**License**: MIT  
**Primary Use Case**: Building modern chat interfaces in SwiftUI applications

## Core Capabilities

### Message Content Types

- **Text**: Styled text with AttributedString or markdown support
- **Media**: Photos and videos with built-in picker
- **Audio**: Voice recording functionality
- **Links**: Automatic link preview generation
- **GIFs/Stickers**: Giphy integration support
- **Attachments**: Multiple media selection support

### Key Features

- Fully customizable message cells
- Built-in media picker with camera/library access
- Pagination and lazy loading
- Message menu actions (reply, edit, delete)
- Swipe actions on messages
- Real-time typing indicators
- Network status indicators
- Keyboard dismissal modes
- Screen rotation handling
- Localization support

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/exyte/Chat.git")
]
```

### Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.7+

### Dependencies

- SwiftUIIntrospect
- ExyteMediaPicker
- FloatingButton
- ActivityIndicatorView

## Basic Implementation

### 1. Minimal Setup

```swift
import ExyteChat
import SwiftUI

struct ChatScreen: View {
    @State private var messages: [Message] = []
    
    var body: some View {
        ChatView(messages: messages) { draft in
            // Handle sending the draft message
            handleSendMessage(draft)
        }
    }
    
    func handleSendMessage(_ draft: DraftMessage) {
        // Convert draft to your Message type
        // Send to your backend
        // Update messages array
    }
}
```

### 2. Message Model Structure

```swift
// The library's Message type structure
struct Message {
    let id: String
    let user: User
    let status: Message.Status?
    let createdAt: Date
    let text: String
    let attachments: [Attachment]
    let recording: Recording?
    let replyMessage: ReplyMessage?
}

struct User {
    let id: String
    let name: String
    let avatarURL: URL?
    let isCurrentUser: Bool
}

struct Attachment {
    let id: String
    let url: URL
    let type: AttachmentType // .image or .video
    let thumbnail: URL?
}
```

## Advanced Configuration

### Chat Types and Reply Modes

```swift
ChatView(
    messages: messages,
    chatType: .conversation,  // or .comments
    replyMode: .quote         // or .answer
) { draft in
    // Handle draft
}
```

**Chat Types:**

- `.conversation`: Latest message at bottom, new messages animate from bottom
- `.comments`: Latest message at top, new messages animate from top

**Reply Modes:**

- `.quote`: Reply appears as newest message, quoting the original
- `.answer`: Reply appears directly below the original message

### Custom Message Builder

```swift
ChatView(messages: messages) { draft in
    // Send handler
} messageBuilder: { message, positionInUserGroup, positionInMessagesSection, 
                   positionInCommentsGroup, showContextMenuClosure, 
                   messageActionClosure, showAttachmentClosure in
    // Custom message cell
    VStack(alignment: .leading) {
        Text(message.user.name)
            .font(.caption)
            .foregroundColor(.gray)
        
        Text(message.text)
            .padding(8)
            .background(message.user.isCurrentUser ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
        
        if !message.attachments.isEmpty {
            ForEach(message.attachments, id: \.id) { attachment in
                AsyncImage(url: attachment.thumbnail) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .frame(maxHeight: 200)
                .onTapGesture {
                    showAttachmentClosure(attachment)
                }
            }
        }
    }
}
```

### Custom Input View

```swift
ChatView(messages: messages) { draft in
    // Send handler
} inputViewBuilder: { textBinding, attachments, inputViewState, 
                     inputViewStyle, inputViewActionClosure, 
                     dismissKeyboardClosure in
    HStack {
        // Camera button
        Button(action: { inputViewActionClosure(.photo) }) {
            Image(systemName: "camera.fill")
        }
        
        // Text field
        TextField("Type a message...", text: textBinding)
            .textFieldStyle(RoundedBorderTextFieldStyle())
        
        // Send button
        Button(action: { inputViewActionClosure(.send) }) {
            Image(systemName: "paperplane.fill")
        }
        .disabled(textBinding.wrappedValue.isEmpty)
    }
    .padding()
}
```

## Message Menu Actions

### Implementing Custom Menu Actions

```swift
enum CustomMenuAction: MessageMenuAction {
    case reply
    case edit
    case delete
    case copy
    case forward
    
    func title() -> String {
        switch self {
        case .reply: return "Reply"
        case .edit: return "Edit"
        case .delete: return "Delete"
        case .copy: return "Copy"
        case .forward: return "Forward"
        }
    }
    
    func icon() -> Image {
        switch self {
        case .reply: return Image(systemName: "arrowshape.turn.up.left")
        case .edit: return Image(systemName: "pencil")
        case .delete: return Image(systemName: "trash")
        case .copy: return Image(systemName: "doc.on.doc")
        case .forward: return Image(systemName: "arrowshape.turn.up.right")
        }
    }
    
    // Conditional menu items based on message
    static func menuItems(for message: Message) -> [CustomMenuAction] {
        if message.user.isCurrentUser {
            return [.edit, .delete, .copy, .forward]
        } else {
            return [.reply, .copy, .forward]
        }
    }
}

// Usage
ChatView(messages: messages) { draft in
    // Send handler
} messageMenuAction: { (action: CustomMenuAction, defaultActionClosure, message) in
    switch action {
    case .reply:
        defaultActionClosure(message, .reply)
    case .edit:
        defaultActionClosure(message, .edit { editedText in
            // Update message on backend
            updateMessage(message.id, text: editedText)
        })
    case .delete:
        deleteMessage(message.id)
    case .copy:
        UIPasteboard.general.string = message.text
    case .forward:
        forwardMessage(message)
    }
}
```

## Swipe Actions

```swift
ChatView(messages: messages) { draft in
    // Send handler
}
.swipeActions(
    edge: .leading,
    performsFirstActionWithFullSwipe: true,
    items: [
        SwipeAction(
            action: { message in deleteMessage(message) },
            activeFor: { $0.user.isCurrentUser },
            background: .red
        ) {
            Label("Delete", systemImage: "trash")
        },
        SwipeAction(
            action: { message in replyToMessage(message) },
            background: .blue
        ) {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
    ]
)
```

## Theming and Customization

### Chat Theme Configuration

```swift
ChatView(messages: messages) { draft in
    // Send handler
}
.chatTheme(
    ChatTheme(
        colors: ChatTheme.Colors(
            mainBackground: Color("ChatBackground"),
            buttonBackground: Color.blue,
            addButtonBackground: Color.green,
            inputViewBackground: Color.gray.opacity(0.1),
            inputTextColor: .primary,
            inputPlaceholderColor: .secondary,
            messageCurrentUserBackground: Color.blue,
            messageOtherUserBackground: Color.gray.opacity(0.2),
            messageCurrentUserTextColor: .white,
            messageOtherUserTextColor: .primary,
            messageTimeTextColor: .secondary,
            sendButtonActiveColor: .blue,
            sendButtonDisabledColor: .gray
        ),
        images: ChatTheme.Images(
            camera: Image(systemName: "camera.fill"),
            send: Image(systemName: "paperplane.fill"),
            attach: Image(systemName: "paperclip"),
            microphone: Image(systemName: "mic.fill"),
            close: Image(systemName: "xmark"),
            background: ChatTheme.Images.Background(
                portraitBackgroundLight: Image("chat_bg_light"),
                portraitBackgroundDark: Image("chat_bg_dark"),
                landscapeBackgroundLight: Image("chat_bg_landscape_light"),
                landscapeBackgroundDark: Image("chat_bg_landscape_dark")
            )
        )
    )
)
```

### View Modifiers

```swift
ChatView(messages: messages) { draft in
    // Send handler
}
// Layout modifiers
.isListAboveInputView(true)
.showDateHeaders(true)
.isScrollEnabled(true)

// Feature toggles
.showMessageMenuOnLongPress(true)
.showNetworkConnectionProblem(true)
.showMessageTimeView(true)

// Input configuration
.setAvailableInputs([.text, .media, .audio, .giphy])
.assetsPickerLimit(10)
.setMediaPickerSelectionParameters(
    MediaPickerParameters(
        mediaType: .photoAndVideo,
        selectionLimit: 5,
        selectionStyle: .ordered
    )
)

// Message configuration
.messageUseMarkdown(true)
.messageLinkPreviewLimit(3)
.linkPreviewsDisabled(false)
.setMessageFont(.system(size: 16))

// Avatar configuration
.avatarSize(40)
.tapAvatarClosure { user in
    showUserProfile(user)
}

// Keyboard behavior
.keyboardDismissMode(.onDrag)
```

## Pagination and Load More

```swift
ChatView(messages: messages) { draft in
    // Send handler
}
.enableLoadMore(offset: 5) { 
    // Load more messages when scrolled to 5th message from end
    loadMoreMessages { newMessages in
        messages.insert(contentsOf: newMessages, at: 0)
    }
}
```

## Giphy Integration

```swift
ChatView(messages: messages) { draft in
    // Send handler
}
.setAvailableInputs([.text, .media, .giphy])
.giphyConfig(
    GiphyConfiguration(
        giphyKey: "YOUR_GIPHY_API_KEY",
        mediaTypeConfig: [.recents, .gifs, .stickers, .clips],
        showAttributionMark: true // Required for production
    )
)
```

## Localization

Add to your `Localizable.strings`:

```strings
"Type a message..." = "Type a message...";
"Add signature..." = "Add signature...";
"Cancel" = "Cancel";
"Recents" = "Recents";
"Waiting for network" = "Waiting for network";
"Recording..." = "Recording...";
"Reply to" = "Reply to";
```

## Additional View Builders

```swift
ChatView(messages: messages) { draft in
    // Send handler
}
// Content between list and input
.betweenListAndInputViewBuilder {
    TypingIndicatorView()
}

// Main header (scrolls with messages)
.mainHeaderBuilder {
    VStack {
        Image("chat_header")
        Text("Customer Support")
            .font(.headline)
    }
}

// Section headers
.headerBuilder { date in
    Text(date, style: .date)
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.vertical, 4)
}
```

## Backend Integration Example

```swift
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    
    func sendMessage(_ draft: DraftMessage) {
        // Create message from draft
        let message = Message(
            id: UUID().uuidString,
            user: currentUser,
            status: .sending,
            createdAt: Date(),
            text: draft.text,
            attachments: draft.attachments.map { convertAttachment($0) },
            recording: draft.recording,
            replyMessage: draft.replyMessage
        )
        
        // Add to local messages
        messages.append(message)
        
        // Send to backend
        APIService.shared.sendMessage(message) { result in
            switch result {
            case .success(let sentMessage):
                // Update message status
                if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
                    self.messages[index] = sentMessage
                }
            case .failure(let error):
                // Handle error
                self.handleSendError(message, error)
            }
        }
    }
}
```

## Performance Optimization

### Best Practices

1. **Message Limiting**: Keep only visible messages in memory

```swift
let visibleMessages = Array(allMessages.suffix(100))
```

1. **Image Caching**: Use Kingfisher for efficient image caching

```swift
// The library handles this automatically for attachments
```

1. **Lazy Loading**: Enable pagination for large message lists

```swift
.enableLoadMore(offset: 10) { 
    // Load previous messages
}
```

1. **Debouncing**: Implement typing indicator debouncing

```swift
private let typingDebouncer = Debouncer(delay: 1.0)

func userTyping() {
    typingDebouncer.debounce {
        sendTypingIndicator(false)
    }
    sendTypingIndicator(true)
}
```

## Troubleshooting

### Common Issues

**Issue**: Messages not appearing

- Ensure `messages` array is properly updated
- Check that message IDs are unique
- Verify `isCurrentUser` is set correctly

**Issue**: Media picker not working

- Add required Info.plist permissions:
  - `NSCameraUsageDescription`
  - `NSPhotoLibraryUsageDescription`
  - `NSMicrophoneUsageDescription`

**Issue**: Custom message cells not showing

- Verify messageBuilder closure returns valid SwiftUI views
- Check that all required parameters are used correctly

**Issue**: Keyboard dismissal issues

- Set appropriate `keyboardDismissMode`
- Use `dismissKeyboardClosure` in custom input views

## Migration Guide

### From UIKit Chat Libraries

1. Replace UITableView/UICollectionView with ChatView
1. Convert message models to library’s Message type
1. Replace custom cells with messageBuilder
1. Update networking layer to work with DraftMessage

### From Other SwiftUI Chat Libraries

1. Map existing message models
1. Update view modifiers to library’s syntax
1. Migrate custom UI components to builders
1. Update gesture recognizers to menu actions

## Example Projects

The library includes two example projects:

1. **ChatExample**: Simple bot demo with random messages
1. **ChatFirestoreExample**: Full Firebase integration

Clone and run:

```bash
git clone https://github.com/exyte/Chat.git
cd Chat
open ChatExample.xcodeproj
```

## Support and Resources

- **GitHub Issues**: https://github.com/exyte/Chat/issues
- **Swift Package Index**: https://swiftpackageindex.com/exyte/Chat
- **Documentation**: Available in repository README
- **License**: MIT License

## Summary for Implementation

As a coding agent, prioritize these implementation steps:

1. **Setup**: Install via SPM, ensure iOS 17+ target
1. **Basic Integration**: Implement minimal ChatView with messages array
1. **Customization**: Apply theme and configure view modifiers
1. **Features**: Add menu actions, swipe actions, and media support
1. **Backend**: Connect to your messaging service
1. **Optimization**: Implement pagination and caching
1. **Testing**: Verify on multiple devices and orientations

Remember to handle all user interactions through the provided closures and maintain message state consistency between the UI and your backend service.
