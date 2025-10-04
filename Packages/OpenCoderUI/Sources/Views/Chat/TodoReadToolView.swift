import SwiftUI
import OpenCoderCore

struct TodoReadToolView: View {
  let toolInfo: EnhancedMessagePart.ToolCallInfo
  @Binding var isExpanded: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: toolStateIcon(toolInfo.state))
          .foregroundColor(toolStateColor(toolInfo.state))

        if let planningInfo = parseTodoReadOutput(toolInfo.output) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Read Tasks")
              .font(.caption)
              .fontWeight(.medium)

            let summary = generateTaskSummary(planningInfo.todos)
            Text(summary)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(2)
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
          if let planningInfo = parseTodoReadOutput(toolInfo.output) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Tasks:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)

              ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                  ForEach(planningInfo.todos, id: \.id) { todo in
                    TodoItemView(todo: todo)
                  }
                }
                .padding(8)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(6)
              }
              .frame(maxHeight: 300)
            }
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

  struct TodoReadOutputInfo {
    let todos: [TodoItem]
  }

  private func parseTodoReadOutput(_ output: String?) -> TodoReadOutputInfo? {
    guard let output = output else { return nil }

    guard let data = output.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    guard let todosArray = json["todos"] as? [[String: Any]] else {
      return nil
    }

    let todos = todosArray.compactMap { todoDict -> TodoItem? in
      guard let id = todoDict["id"] as? String,
            let content = todoDict["content"] as? String,
            let status = todoDict["status"] as? String,
            let priority = todoDict["priority"] as? String else {
        return nil
      }
      return TodoItem(id: id, content: content, status: status, priority: priority)
    }

    return TodoReadOutputInfo(todos: todos)
  }

  private func generateTaskSummary(_ todos: [TodoItem]) -> String {
    let total = todos.count
    let completed = todos.filter { $0.status == "completed" }.count
    let inProgress = todos.filter { $0.status == "in_progress" }.count
    let pending = todos.filter { $0.status == "pending" }.count

    var parts: [String] = []
    parts.append("\(total) task\(total == 1 ? "" : "s")")

    if completed > 0 {
      parts.append("\(completed) completed")
    }
    if inProgress > 0 {
      parts.append("\(inProgress) in progress")
    }
    if pending > 0 {
      parts.append("\(pending) pending")
    }

    return parts.joined(separator: ", ")
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
