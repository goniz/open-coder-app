import SwiftUI
import OpenCoderCore
import ExyteChat

// MARK: - Part Renderer Protocol

public protocol MessagePartRenderer {
  associatedtype Body: View

  func canRender(_ part: EnhancedMessagePart) -> Bool
  func render(_ part: EnhancedMessagePart, message: Message) -> Body
}

public struct AnyMessagePartRenderer {
  private let _canRender: (EnhancedMessagePart) -> Bool
  private let _render: (EnhancedMessagePart, Message) -> AnyView

  public init<R: MessagePartRenderer>(_ renderer: R) {
    self._canRender = renderer.canRender
    self._render = { part, message in
      AnyView(renderer.render(part, message: message))
    }
  }

  public func canRender(_ part: EnhancedMessagePart) -> Bool {
    _canRender(part)
  }

  public func render(_ part: EnhancedMessagePart, message: Message) -> AnyView {
    _render(part, message)
  }
}

// MARK: - Enhanced Message Part Types

public enum EnhancedMessagePart: Equatable, Sendable {
  case text(String)
  case reasoning(String)
  case file(path: String, content: String, operation: FileOperation)
  case tool(ToolCallInfo)
  case stepStart(String, stepID: String)
  case stepFinish(String, stepID: String, success: Bool)
  case snapshot(String, snapshotID: String)
  case patch(String, filePath: String, diff: String)
  case agent(String, agentType: String)

  public enum FileOperation: String, Equatable, Sendable {
    case read, write, create, delete, rename
  }

  public struct ToolCallInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public let state: ToolState
    public let input: String?
    public let output: String?
    public let error: String?

    public init(
      id: String,
      name: String,
      state: ToolState,
      input: String? = nil,
      output: String? = nil,
      error: String? = nil
    ) {
      self.id = id
      self.name = name
      self.state = state
      self.input = input
      self.output = output
      self.error = error
    }
  }

  public enum ToolState: String, Equatable, Sendable {
    case pending, running, completed, error
  }
}

// MARK: - Default Part Renderers

public struct TextPartRenderer: MessagePartRenderer {
  public func canRender(_ part: EnhancedMessagePart) -> Bool {
    if case .text = part { return true }
    return false
  }

  public func render(_ part: EnhancedMessagePart, message: Message) -> some View {
    Group {
      if case let .text(content) = part {
        if message.user.isCurrentUser {
          Text(content)
            .font(.body)
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          let markdownContent = preprocessMarkdown(content)
          if let attributedString = try? AttributedString(markdown: markdownContent) {
            Text(attributedString)
              .font(.body)
              .foregroundColor(.primary)
              .lineSpacing(3)
              .fixedSize(horizontal: false, vertical: true)
          } else {
            Text(content)
              .font(.body)
              .foregroundColor(.primary)
              .lineSpacing(3)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      } else {
        EmptyView()
      }
    }
  }

  private func preprocessMarkdown(_ text: String) -> String {
    // Normalize newlines
    var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                         .replacingOccurrences(of: "\r", with: "\n")
    // Collapse 3+ newlines into 2
    while normalized.contains("\n\n\n") {
      normalized = normalized.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
    // Split into paragraphs by double newline
    let paragraphs = normalized.components(separatedBy: "\n\n")
    // Replace single newlines inside paragraphs with spaces
    let cleaned = paragraphs.map { $0.replacingOccurrences(of: "\n", with: " ") }
    // Re-join paragraphs with a single blank line
    return cleaned.joined(separator: "\n\n")
  }
}

public struct ReasoningPartRenderer: MessagePartRenderer {
  public func canRender(_ part: EnhancedMessagePart) -> Bool {
    if case .reasoning = part { return true }
    return false
  }

  public func render(_ part: EnhancedMessagePart, message: Message) -> some View {
    Group {
      if case let .reasoning(content) = part {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Image(systemName: "brain.head.profile")
              .foregroundColor(.orange)
            Text("Reasoning")
              .font(.caption)
              .foregroundColor(.orange)
              .fontWeight(.medium)
          }

          Text(content)
            .font(.body)
            .foregroundColor(.secondary)
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
      } else {
        EmptyView()
      }
    }
  }
}

public struct FilePartRenderer: MessagePartRenderer {
  public func canRender(_ part: EnhancedMessagePart) -> Bool {
    if case .file = part { return true }
    return false
  }

  public func render(_ part: EnhancedMessagePart, message: Message) -> some View {
    Group {
      if case let .file(path, content, operation) = part {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Image(systemName: fileOperationIcon(operation))
              .foregroundColor(fileOperationColor(operation))
            Text(fileOperationText(operation, path: path))
              .font(.caption)
              .foregroundColor(fileOperationColor(operation))
              .fontWeight(.medium)
          }

          FileContentView(path: path, content: content, operation: operation)
        }
      } else {
        EmptyView()
      }
    }
  }

  private func fileOperationIcon(_ operation: EnhancedMessagePart.FileOperation) -> String {
    switch operation {
    case .read: return "doc.text"
    case .write: return "doc.fill.badge.plus"
    case .create: return "doc.badge.plus"
    case .delete: return "doc.badge.minus"
    case .rename: return "doc.badge.arrow.right"
    }
  }

  private func fileOperationColor(_ operation: EnhancedMessagePart.FileOperation) -> Color {
    switch operation {
    case .read: return .blue
    case .write, .create: return .green
    case .delete: return .red
    case .rename: return .orange
    }
  }

  private func fileOperationText(_ operation: EnhancedMessagePart.FileOperation, path: String) -> String {
    switch operation {
    case .read: return "Reading file: \(path)"
    case .write: return "Writing to: \(path)"
    case .create: return "Creating file: \(path)"
    case .delete: return "Deleting: \(path)"
    case .rename: return "Renaming: \(path)"
    }
  }
}

public struct ToolPartRenderer: MessagePartRenderer {
  public func canRender(_ part: EnhancedMessagePart) -> Bool {
    if case .tool = part { return true }
    return false
  }

  public func render(_ part: EnhancedMessagePart, message: Message) -> some View {
    Group {
      if case let .tool(toolInfo) = part {
        ToolCallView(toolInfo: toolInfo)
      } else {
        EmptyView()
      }
    }
  }
}

public struct StepPartRenderer: MessagePartRenderer {
  public func canRender(_ part: EnhancedMessagePart) -> Bool {
    if case .stepStart = part { return true }
    if case .stepFinish = part { return true }
    return false
  }

  public func render(_ part: EnhancedMessagePart, message: Message) -> some View {
    Group {
      if case let .stepStart(text, stepID) = part {
        StepView(text: text, stepID: stepID, isStart: true)
      } else if case let .stepFinish(text, stepID, success) = part {
        StepView(text: text, stepID: stepID, isStart: false, success: success)
      } else {
        EmptyView()
      }
    }
  }
}

public struct PatchPartRenderer: MessagePartRenderer {
  public func canRender(_ part: EnhancedMessagePart) -> Bool {
    if case .patch = part { return true }
    return false
  }

  public func render(_ part: EnhancedMessagePart, message: Message) -> some View {
    Group {
      if case let .patch(text, filePath, diff) = part {
        PatchView(title: text, filePath: filePath, diff: diff)
      } else {
        EmptyView()
      }
    }
  }
}

public struct AgentPartRenderer: MessagePartRenderer {
  public func canRender(_ part: EnhancedMessagePart) -> Bool {
    if case .agent = part { return true }
    return false
  }

  public func render(_ part: EnhancedMessagePart, message: Message) -> some View {
    Group {
      if case let .agent(content, agentType) = part {
        AgentView(content: content, agentType: agentType)
      } else {
        EmptyView()
      }
    }
  }
}

// MARK: - Supporting Views

struct FileContentView: View {
  let path: String
  let content: String
  let operation: EnhancedMessagePart.FileOperation

  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button(action: { isExpanded.toggle() }) {
        HStack {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption)
          Text(path)
            .font(.caption)
            .lineLimit(1)
          Spacer()
        }
        .foregroundColor(.secondary)
      }

      if isExpanded {
        ScrollView {
          Text(content)
            .font(.system(.caption, design: .monospaced))
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        }
        .frame(maxHeight: 200)
      }
    }
  }
}

struct ToolCallView: View {
  let toolInfo: EnhancedMessagePart.ToolCallInfo

  @State private var isExpanded = false

  var body: some View {
    if toolInfo.name == "read" {
      ReadToolView(toolInfo: toolInfo, isExpanded: $isExpanded)
    } else if toolInfo.name == "bash" {
      BashToolView(toolInfo: toolInfo, isExpanded: $isExpanded)
    } else if toolInfo.name == "edit" {
      EditToolView(toolInfo: toolInfo, isExpanded: $isExpanded)
    } else if toolInfo.name == "todowrite" {
      PlanningToolView(toolInfo: toolInfo, isExpanded: $isExpanded)
    } else if toolInfo.name == "todoread" {
      TodoReadToolView(toolInfo: toolInfo, isExpanded: $isExpanded)
    } else {
      GenericToolCallView(toolInfo: toolInfo, isExpanded: $isExpanded)
    }
  }
}

struct GenericToolCallView: View {
  let toolInfo: EnhancedMessagePart.ToolCallInfo
  @Binding var isExpanded: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: toolStateIcon(toolInfo.state))
          .foregroundColor(toolStateColor(toolInfo.state))

        VStack(alignment: .leading, spacing: 2) {
          Text(toolInfo.name)
            .font(.caption)
            .fontWeight(.medium)

          Text(toolStateText(toolInfo.state))
            .font(.caption2)
            .foregroundColor(.secondary)
        }

        Spacer()

        if toolInfo.state == .running {
          ProgressView()
            .scaleEffect(0.8)
        }

        Button(action: { isExpanded.toggle() }) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption)
        }
      }

      if isExpanded {
        VStack(alignment: .leading, spacing: 8) {
          if let input = toolInfo.input, !input.isEmpty {
            CopyableTextSection(
              title: "Input",
              content: input,
              backgroundColor: Color.gray.opacity(0.1),
              titleColor: .primary
            )
          }

          if let output = toolInfo.output, !output.isEmpty {
            CopyableTextSection(
              title: "Output",
              content: output,
              backgroundColor: Color.green.opacity(0.1),
              titleColor: .primary
            )
          }

          if let error = toolInfo.error, !error.isEmpty {
            CopyableTextSection(
              title: "Error",
              content: error,
              backgroundColor: Color.red.opacity(0.1),
              titleColor: .red
            )
          }
        }
      }
    }
    .padding(8)
    .background(toolStateBackgroundColor(toolInfo.state))
    .cornerRadius(8)
  }

  private func toolStateIcon(_ state: EnhancedMessagePart.ToolState) -> String {
    switch state {
    case .pending: return "clock"
    case .running: return "play.circle"
    case .completed: return "checkmark.circle.fill"
    case .error: return "xmark.circle.fill"
    }
  }

  private func toolStateColor(_ state: EnhancedMessagePart.ToolState) -> Color {
    switch state {
    case .pending: return .orange
    case .running: return .blue
    case .completed: return .green
    case .error: return .red
    }
  }

  private func toolStateText(_ state: EnhancedMessagePart.ToolState) -> String {
    switch state {
    case .pending: return "Pending"
    case .running: return "Running..."
    case .completed: return "Completed"
    case .error: return "Error"
    }
  }

  private func toolStateBackgroundColor(_ state: EnhancedMessagePart.ToolState) -> Color {
    switch state {
    case .pending: return Color.orange.opacity(0.1)
    case .running: return Color.blue.opacity(0.1)
    case .completed: return Color.green.opacity(0.1)
    case .error: return Color.red.opacity(0.1)
    }
  }
}

struct StepView: View {
  let text: String
  let stepID: String
  let isStart: Bool
  var success: Bool = true

  var body: some View {
    HStack {
      Image(systemName: isStart ? "play.circle" : (success ? "checkmark.circle.fill" : "xmark.circle.fill"))
        .foregroundColor(isStart ? .blue : (success ? .green : .red))
        .font(.caption2)

      Text(text)
        .font(.caption2)
        .foregroundColor(.secondary.opacity(0.8))

      Spacer()
    }
    .padding(6)
    .background(Color.gray.opacity(0.03))
    .cornerRadius(6)
  }
}

struct PatchView: View {
  let title: String
  let filePath: String
  let diff: String

  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "doc.text")
          .foregroundColor(.green)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.caption)
            .fontWeight(.medium)

          Text(filePath)
            .font(.caption2)
            .foregroundColor(.secondary)
        }

        Spacer()

        Button(action: { isExpanded.toggle() }) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption)
        }
      }

      if isExpanded && !diff.isEmpty {
        ScrollView {
          Text(diff)
            .font(.system(.caption, design: .monospaced))
            .padding(8)
            .background(Color.green.opacity(0.1))
            .cornerRadius(6)
        }
        .frame(maxHeight: 200)
      }
    }
    .padding(8)
    .background(Color.green.opacity(0.05))
    .cornerRadius(8)
  }
}

struct AgentView: View {
  let content: String
  let agentType: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "person.2.fill")
          .foregroundColor(.purple)

        Text("Agent: \(agentType)")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(.purple)
      }

      Text(content)
        .font(.body)
        .foregroundColor(.primary)
    }
    .padding(8)
    .background(Color.purple.opacity(0.1))
    .cornerRadius(8)
  }
}

struct CopyableTextSection: View {
  let title: String
  let content: String
  let backgroundColor: Color
  let titleColor: Color

  @State private var showCopiedFeedback = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("\(title):")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(titleColor)

        Spacer()

        Button(action: copyToClipboard) {
          HStack(spacing: 4) {
            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
              .font(.caption)
            if showCopiedFeedback {
              Text("Copied")
                .font(.caption2)
            }
          }
          .foregroundColor(showCopiedFeedback ? .green : .secondary)
        }
      }

      ScrollView {
        Text(content)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .background(backgroundColor)
          .cornerRadius(6)
      }
      .frame(maxHeight: 200)
    }
  }

  private func copyToClipboard() {
    #if os(iOS)
    UIPasteboard.general.string = content
    #elseif os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(content, forType: .string)
    #endif

    showCopiedFeedback = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      showCopiedFeedback = false
    }
  }
}
