import Foundation
import OSLog

@MainActor
package final class AppLogger: ObservableObject {
  package static let shared = AppLogger()

  @Published package var logEntries: [LogEntry] = []
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "OpenCoder", category: "AppLogger")

  private init() {}

  package func log(_ message: String, level: LogLevel = .info, category: LogCategory = .general) {
    let entry = LogEntry(
      timestamp: Date(),
      message: message,
      level: level,
      category: category
    )

    logEntries.append(entry)

    // Keep only last 1000 entries to prevent memory issues
    if logEntries.count > 1000 {
      logEntries.removeFirst(logEntries.count - 1000)
    }

    // Log to system logger as well
    switch level {
    case .debug:
      logger.debug("\(message)")
    case .info:
      logger.info("\(message)")
    case .warning:
      logger.warning("\(message)")
    case .error:
      logger.error("\(message)")
    }
  }

  package func clearLogs() {
    logEntries.removeAll()
  }
}

package struct LogEntry: Identifiable, Equatable {
  package let id = UUID()
  package let timestamp: Date
  package let message: String
  package let level: LogLevel
  package let category: LogCategory

  package var formattedTimestamp: String {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    formatter.dateStyle = .none
    return formatter.string(from: timestamp)
  }
}

package enum LogLevel: String, CaseIterable {
  case debug = "DEBUG"
  case info = "INFO"
  case warning = "WARNING"
  case error = "ERROR"

  package var color: String {
    switch self {
    case .debug: return "gray"
    case .info: return "blue"
    case .warning: return "orange"
    case .error: return "red"
    }
  }
}

package enum LogCategory: String, CaseIterable {
  case general = "General"
  case ssh = "SSH"
  case api = "API"
  case workspace = "Workspace"
  case fileSystem = "FileSystem"
}
