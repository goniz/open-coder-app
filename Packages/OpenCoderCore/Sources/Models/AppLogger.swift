import Foundation
import OSLog

@MainActor
public final class AppLogger: ObservableObject {
  public static let shared = AppLogger()

  @Published public var logEntries: [LogEntry] = []
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "OpenCoder", category: "AppLogger")

  public var latestEntryID: LogEntry.ID? {
    logEntries.last?.id
  }

  private init() {}

  public func log(_ message: String, level: LogLevel = .info, category: LogCategory = .general) {
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

  public func clearLogs() {
    logEntries.removeAll()
  }
}

public struct LogEntry: Identifiable, Equatable, Sendable {

  public let id = UUID()
  public let timestamp: Date
  public let message: String
  public let level: LogLevel
  public let category: LogCategory

  public var formattedTimestamp: String {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    formatter.dateStyle = .none
    return formatter.string(from: timestamp)
  }
}

public enum LogLevel: String, CaseIterable, Sendable {

  case debug = "DEBUG"
  case info = "INFO"
  case warning = "WARNING"
  case error = "ERROR"

  public var color: String {
    switch self {
    case .debug: return "gray"
    case .info: return "blue"
    case .warning: return "orange"
    case .error: return "red"
    }
  }
}

public enum LogCategory: String, CaseIterable, Sendable {

  case general = "General"
  case ssh = "SSH"
  case api = "API"
  case workspace = "Workspace"
  case fileSystem = "FileSystem"
}
