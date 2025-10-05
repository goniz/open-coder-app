import SwiftUI
import OpenCoderCore

struct ReadToolView: View {
  let toolInfo: EnhancedMessagePart.ToolCallInfo
  @Binding var isExpanded: Bool
  @Environment(\.workspaceRemotePath) var workspaceRemotePath

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: toolStateIcon(toolInfo.state))
          .foregroundColor(toolStateColor(toolInfo.state))

        if let readInfo = parseReadToolInput(toolInfo.input) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Read")
              .font(.caption)
              .fontWeight(.medium)

            Text(readInfo.relativePath)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(2)

            if let offset = readInfo.offset, let limit = readInfo.limit {
              Text("\(offset):\(limit)")
                .font(.caption2)
                .foregroundColor(.secondary)
            } else if let limit = readInfo.limit {
              Text(":\(limit)")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
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
          if let output = toolInfo.output, !output.isEmpty {
            let cleanedOutput = cleanReadToolOutput(output)
            CopyableTextSection(
              title: "Output",
              content: cleanedOutput,
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

  struct ReadToolInputInfo {
    let relativePath: String
    let offset: Int?
    let limit: Int?
  }

  private func parseReadToolInput(_ input: String?) -> ReadToolInputInfo? {
    guard let input = input else { return nil }

    guard let data = input.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    guard let filePath = json["filePath"] as? String else { return nil }

    let relativePath = makeRelativePath(filePath)
    let offset = json["offset"] as? Int
    let limit = json["limit"] as? Int

    return ReadToolInputInfo(relativePath: relativePath, offset: offset, limit: limit)
  }

  private func makeRelativePath(_ fullPath: String) -> String {
    if let remotePath = workspaceRemotePath, fullPath.hasPrefix(remotePath + "/") {
      return String(fullPath.dropFirst(remotePath.count + 1))
    } else {
      return (fullPath as NSString).lastPathComponent
    }
  }

  private func cleanReadToolOutput(_ output: String) -> String {
    var cleaned = output

    if cleaned.hasPrefix("<file>") {
      cleaned = String(cleaned.dropFirst("<file>".count))
    }
    if cleaned.hasSuffix("</file>") {
      cleaned = String(cleaned.dropLast("</file>".count))
    }

    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

    let lines = cleaned.components(separatedBy: .newlines)
    let cleanedLines = lines.map { line -> String in
      if let match = line.firstMatch(of: /^(\s*)(\d+)\|(.*)$/) {
        return String(match.3)
      }
      return line
    }

    return cleanedLines.joined(separator: "\n")
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
