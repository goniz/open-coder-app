import SwiftUI
import OpenCoderCore

struct EditToolView: View {
  let toolInfo: EnhancedMessagePart.ToolCallInfo
  @Binding var isExpanded: Bool
  @Environment(\.workspaceRemotePath) var workspaceRemotePath

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: toolStateIcon(toolInfo.state))
          .foregroundColor(toolStateColor(toolInfo.state))

        if let editInfo = parseEditToolInput(toolInfo.input) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Edit")
              .font(.caption)
              .fontWeight(.medium)

            Text(editInfo.relativePath)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(1)

            if let diffSummary = generateDiffSummary(old: editInfo.oldString, new: editInfo.newString) {
              Text(diffSummary)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
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
          if let editInfo = parseEditToolInput(toolInfo.input) {
            CopyableTextSection(
              title: "Diff",
              content: generateDiff(old: editInfo.oldString, new: editInfo.newString),
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

  struct EditToolInputInfo {
    let relativePath: String
    let oldString: String
    let newString: String
    let replaceAll: Bool?
  }

  private func parseEditToolInput(_ input: String?) -> EditToolInputInfo? {
    guard let input = input else { return nil }

    guard let data = input.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    guard let filePath = json["filePath"] as? String,
          let oldString = json["oldString"] as? String,
          let newString = json["newString"] as? String else {
      return nil
    }

    let relativePath = makeRelativePath(filePath)
    let replaceAll = json["replaceAll"] as? Bool

    return EditToolInputInfo(
      relativePath: relativePath,
      oldString: oldString,
      newString: newString,
      replaceAll: replaceAll
    )
  }

  private func makeRelativePath(_ fullPath: String) -> String {
    if let remotePath = workspaceRemotePath, fullPath.hasPrefix(remotePath + "/") {
      return String(fullPath.dropFirst(remotePath.count + 1))
    } else {
      return (fullPath as NSString).lastPathComponent
    }
  }

  private func generateDiff(old: String, new: String) -> String {
    let oldLines = old.components(separatedBy: "\n")
    let newLines = new.components(separatedBy: "\n")
    let maxLines = max(oldLines.count, newLines.count)
    var diff = ""

    for index in 0..<maxLines {
      let oldLine = index < oldLines.count ? oldLines[index] : ""
      let newLine = index < newLines.count ? newLines[index] : ""

      if oldLine != newLine {
        if !oldLine.isEmpty || (oldLine.isEmpty && index >= oldLines.count) {
          diff += "-\(oldLine)\n"
        }
        if !newLine.isEmpty || (newLine.isEmpty && index >= newLines.count) {
          diff += "+\(newLine)\n"
        }
      }
    }

    return diff.isEmpty ? "No changes" : diff
  }

  private func generateDiffSummary(old: String, new: String) -> String? {
    let diff = generateDiff(old: old, new: new)
    if diff == "No changes" { return nil }
    let lines = diff.components(separatedBy: "\n").filter { !$0.isEmpty }
    let additions = lines.filter { $0.hasPrefix("+") }.count
    let deletions = lines.filter { $0.hasPrefix("-") }.count
    return "\(additions) additions, \(deletions) deletions"
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
