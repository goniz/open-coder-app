import SwiftUI
import OpenCoderCore

struct BashToolView: View {
  let toolInfo: EnhancedMessagePart.ToolCallInfo
  @Binding var isExpanded: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: toolStateIcon(toolInfo.state))
          .foregroundColor(toolStateColor(toolInfo.state))

        if let bashInfo = parseBashToolInput(toolInfo.input) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Bash")
              .font(.caption)
              .fontWeight(.medium)

            Text(bashInfo.description)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(2)

            Text(bashInfo.command)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
        } else {
          VStack(alignment: .leading, spacing: 2) {
            Text(toolInfo.name)
              .font(.caption)
              .fontWeight(.medium)

            Text(toolStateText(toolInfo.state))
              .font(.caption2)
              .foregroundColor(.secondary)
          }
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
          if let bashInfo = parseBashToolInput(toolInfo.input) {
            CopyableTextSection(
              title: "Command",
              content: bashInfo.command,
              backgroundColor: Color.blue.opacity(0.1),
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

  struct BashToolInputInfo {
    let command: String
    let description: String
  }

  private func parseBashToolInput(_ input: String?) -> BashToolInputInfo? {
    guard let input = input else { return nil }

    guard let data = input.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    guard let command = json["command"] as? String,
          let description = json["description"] as? String else {
      return nil
    }

    return BashToolInputInfo(command: command, description: description)
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
