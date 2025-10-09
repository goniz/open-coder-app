import Foundation
import OSLog

#if canImport(SwiftUI)
import SwiftUI
#endif

@MainActor
public final class AppLogger: ObservableObject {
  public static let shared = AppLogger()

  @Published public var logEntries: [LogEntry] = []
  @Published public var previousLaunchLogs: [LogEntry] = []
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "OpenCoder", category: "AppLogger")

  private let maxLogsPerSession = 1000
  private let maxPreviousLogs = 2000
  private var saveTask: Task<Void, Never>?
  private var hasPendingSave = false

  private var documentsDirectory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
  }

  private var currentLogsURL: URL {
    documentsDirectory.appendingPathComponent("current_logs.json")
  }

  private var previousLogsURL: URL {
    documentsDirectory.appendingPathComponent("previous_logs.json")
  }

  public var latestEntryID: LogEntry.ID? {
    logEntries.last?.id
  }

  public var recentLogs: [LogEntry] {
    logEntries
  }

  private init() {
    loadPreviousLogs()
    rotateLogs()
  }

  public func log(_ message: String, level: LogLevel = .info, category: LogCategory = .general) {
    let entry = LogEntry(
      timestamp: Date(),
      message: message,
      level: level,
      category: category
    )

    logEntries.append(entry)

    // Keep only last entries to prevent memory issues
    if logEntries.count > maxLogsPerSession {
      logEntries.removeFirst(logEntries.count - maxLogsPerSession)
    }

    // Log to system logger as well
    switch level {
    case .trace:
      logger.debug("\(message)")
    case .debug:
      logger.debug("\(message)")
    case .info:
      logger.info("\(message)")
    case .warning:
      logger.warning("\(message)")
    case .error:
      logger.error("\(message)")
    }

    // Debounced save: only save after 2 seconds of no new logs
    debouncedSave()
  }

  private func debouncedSave() {
    saveTask?.cancel()
    hasPendingSave = true

    saveTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled, hasPendingSave else { return }
      await saveCurrentLogs()
      hasPendingSave = false
    }
  }

  public func clearLogs() {
    logEntries.removeAll()
    saveTask?.cancel()
    Task {
      await saveCurrentLogs()
      hasPendingSave = false
    }
  }

  public func clearPreviousLogs() {
    previousLaunchLogs.removeAll()
    saveTask?.cancel()
    Task {
      await savePreviousLogs()
      hasPendingSave = false
    }
  }

  public func flush() async {
    saveTask?.cancel()
    if hasPendingSave {
      await saveCurrentLogs()
      hasPendingSave = false
    }
  }

  public func exportLogsToFile() async -> URL? {
    let tempDir = FileManager.default.temporaryDirectory
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let fileName = "opencoder_logs_\(timestamp).txt"
    let fileURL = tempDir.appendingPathComponent(fileName)

    var logText = "OpenCoder Current Session Logs\n"
    logText += "Generated: \(timestamp)\n"
    logText += "===========================================\n\n"

    if !logEntries.isEmpty {
      logText += "CURRENT SESSION LOGS (\(logEntries.count) entries)\n"
      logText += "===========================================\n"
      for entry in logEntries {
        logText += entry.clipboardText + "\n"
      }
    } else {
      logText += "No logs in current session\n"
    }

    do {
      try logText.write(to: fileURL, atomically: true, encoding: .utf8)
      return fileURL
    } catch {
      logger.error("Failed to export logs: \(error.localizedDescription)")
      return nil
    }
  }

  private func rotateLogs() {
    // Move current logs to previous logs if they exist
    if FileManager.default.fileExists(atPath: currentLogsURL.path) {
      do {
        let currentLogsData = try Data(contentsOf: currentLogsURL)
        let currentLogs = try JSONDecoder().decode([LogEntry].self, from: currentLogsData)

        // Append to existing previous logs
        var allPreviousLogs = previousLaunchLogs + currentLogs

        // Keep only the most recent logs to prevent excessive storage
        if allPreviousLogs.count > maxPreviousLogs {
          allPreviousLogs = Array(allPreviousLogs.suffix(maxPreviousLogs))
        }

        previousLaunchLogs = allPreviousLogs
        Task {
          await savePreviousLogs()
        }

        // Clear current logs file
        try? FileManager.default.removeItem(at: currentLogsURL)

        logger.info("Rotated \(currentLogs.count) logs from previous launch")
      } catch {
        logger.error("Failed to rotate logs: \(error.localizedDescription)")
      }
    }
  }

  private func loadPreviousLogs() {
    guard FileManager.default.fileExists(atPath: previousLogsURL.path) else {
      return
    }

    do {
      let data = try Data(contentsOf: previousLogsURL)
      previousLaunchLogs = try JSONDecoder().decode([LogEntry].self, from: data)
      logger.info("Loaded \(self.previousLaunchLogs.count) logs from previous launches")
    } catch {
      logger.error("Failed to load previous logs: \(error.localizedDescription)")
      previousLaunchLogs = []
    }
  }

  private func saveCurrentLogs() async {
    do {
      let data = try JSONEncoder().encode(logEntries)
      try data.write(to: currentLogsURL)
    } catch {
      logger.error("Failed to save current logs: \(error.localizedDescription)")
    }
  }

  private func savePreviousLogs() async {
    do {
      let data = try JSONEncoder().encode(previousLaunchLogs)
      try data.write(to: previousLogsURL)
    } catch {
      logger.error("Failed to save previous logs: \(error.localizedDescription)")
    }
  }
}

public struct LogEntry: Identifiable, Equatable, Sendable, Codable {

  public let id: UUID
  public let timestamp: Date
  public let message: String
  public let level: LogLevel
  public let category: LogCategory

  public init(timestamp: Date, message: String, level: LogLevel, category: LogCategory) {
    self.id = UUID()
    self.timestamp = timestamp
    self.message = message
    self.level = level
    self.category = category
  }

  public var formattedTimestamp: String {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    formatter.dateStyle = .none
    return formatter.string(from: timestamp)
  }

  public var clipboardText: String {
    "[\(formattedTimestamp)] [\(level.rawValue)] [\(category.rawValue)] \(message)"
  }
}

public enum LogLevel: String, CaseIterable, Sendable, Codable {

  case trace = "TRACE"
  case debug = "DEBUG"
  case info = "INFO"
  case warning = "WARNING"
  case error = "ERROR"

  public var colorString: String {
    switch self {
    case .trace: return "gray"
    case .debug: return "gray"
    case .info: return "blue"
    case .warning: return "orange"
    case .error: return "red"
    }
  }

  #if canImport(SwiftUI)
  @available(iOS 13.0, macOS 10.15, *)
  public var color: Color {
    switch self {
    case .trace: return .secondary
    case .debug: return .gray
    case .info: return .blue
    case .warning: return .orange
    case .error: return .red
    }
  }
  #endif

  public var icon: String {
    switch self {
    case .trace: return "ant.circle"
    case .debug: return "info.circle"
    case .info: return "info.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .error: return "exclamationmark.circle.fill"
    }
  }
}

public enum LogCategory: String, CaseIterable, Sendable, Codable {

  case general = "General"
  case ssh = "SSH"
  case api = "API"
  case workspace = "Workspace"
  case fileSystem = "FileSystem"
  case app = "App"
  case chat = "Chat"
  case activity = "Activity"
}
