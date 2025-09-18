import Foundation
import Models

struct TmuxService: Sendable {
  private let config: Models.SSHServerConfiguration

  init(config: Models.SSHServerConfiguration) {
    self.config = config
  }

  func hasSession(_ name: TmuxSessionName) async throws -> Bool {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      return try await connectionManager.withConnection { connection in
        let escapedName = escapeShellArgument(name.value)
        let command = "tmux has-session -t \(escapedName) 2>/dev/null && echo 'exists' || echo 'not found'"
        let result = try await connection.exec(command)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "exists"
      }
    } catch {
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux session check was cancelled. This may be due to network issues or server timeout.")
      }

      throw error
    }
  }

  enum NewSessionResult: Equatable {
    case created
    case existing
  }

  @discardableResult
  func newSession(name: TmuxSessionName, path: String) async throws -> NewSessionResult {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      return try await connectionManager.withConnection { connection in
        let escapedName = escapeShellArgument(name.value)
        let escapedPath = escapeShellArgument(path)
        let command = "tmux new-session -d -s \(escapedName) -c \(escapedPath)"
        do {
          _ = try await connection.exec(command)
          await AppLogger.shared.log(
            "Created tmux session: \(name.value) at \(path)",
            level: .info,
            category: .workspace
          )
          return .created
        } catch {
          if case let SSHError.commandFailed(message) = error,
            message.lowercased().contains("duplicate session") {
            await AppLogger.shared.log(
              "Using existing tmux session: \(name.value)",
              level: .info,
              category: .workspace
            )
            return .existing
          }
          throw error
        }
      }
    } catch {
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux session creation was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  func newOrReplaceServerWindow(name: TmuxSessionName) async throws {
    do {
      let workspacePath = "$HOME"
      let sessionResult = try await newSession(name: name, path: workspacePath)

      guard sessionResult == .existing else { return }

      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      try await connectionManager.withConnection { connection in
        let escapedName = escapeShellArgument(name.value)
        let killCommand = "tmux kill-session -t \(escapedName)"
        _ = try await connection.exec(killCommand)
      }

      _ = try await newSession(name: name, path: workspacePath)
    } catch {
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux server window setup was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  func listSessions() async throws -> [TmuxSessionName] {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      return try await connectionManager.withConnection { connection in
        let command = "tmux list-sessions -F '#{session_name}' 2>/dev/null || true"
        let result = try await connection.exec(command)
        return result
          .split(separator: "\n")
          .compactMap { line -> TmuxSessionName? in
            let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            return TmuxSessionName(rawValue: normalized)
          }
      }
    } catch {
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux session listing was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  func listWindows(session: TmuxSessionName) async throws -> [String] {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      return try await connectionManager.withConnection { connection in
        let escapedSession = escapeShellArgument(session.value)
        let command =
          "tmux list-windows -t \(escapedSession) -F '#{window_name}' 2>/dev/null || true"
        let result = try await connection.exec(command)
        return result
          .split(separator: "\n")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      }
    } catch {
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux window listing was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  func killSession(_ name: TmuxSessionName) async throws {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      try await connectionManager.withConnection { connection in
        let escapedName = escapeShellArgument(name.value)
        let command = "tmux kill-session -t \(escapedName) 2>/dev/null || true"
        _ = try await connection.exec(command)
      }
    } catch {
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux session kill was cancelled. This may be due to network issues or server timeout.")
      }

      throw error
    }
  }
}

extension TmuxService {
  /// Builds a tmux streaming command that tails the pane's live output.
  func paneStreamingCommand(
    session: TmuxSessionName,
    window: String
  ) -> String {
    let script = paneStreamingScript(
      session: session,
      window: window
    )
    return "bash -lc \(escapeShellArgument(script))"
  }

  /// Captures the current buffer of a tmux pane for initial rendering or post-exit inspection.
  func paneSnapshot(
    session: TmuxSessionName,
    window: String,
    lineCount: Int = 200
  ) async throws -> [String] {
    let connectionManager = await SSHConnectionPool.shared.manager(for: config)
    return try await connectionManager.withConnection { connection in
      let escapedSession = escapeShellArgument(session.value)
      let escapedWindow = escapeShellArgument(window)
      let command =
        "tmux capture-pane -p -J -t \(escapedSession):\(escapedWindow) -S -\(max(1, lineCount)) 2>/dev/null || true"
      let output = try await connection.exec(command)
      return output
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
          line.replacingOccurrences(of: "\r", with: "")
        }
    }
  }

  /// Constructs the shell script used to stream a tmux pane and emit fallback messaging.
  func paneStreamingScript(
    session: TmuxSessionName,
    window: String
  ) -> String {
    let target = "\(session.value):\(window)"
    let escapedTarget = escapeShellArgument(target)
    return """
    tmux_target=\(escapedTarget)
    pane_tty=$(tmux display-message -p -t "$tmux_target" -F '#{pane_tty}' 2>/dev/null || true)
    if [ -z "$pane_tty" ] || [ ! -e "$pane_tty" ]; then
      printf '[Live Output] tmux pane closed (%s).\\n' "$tmux_target"
      exit 0
    fi
    exec cat "$pane_tty"
    """
  }

  func ensureWindow(session: TmuxSessionName, window: String, path: String) async throws {
    let connectionManager = await SSHConnectionPool.shared.manager(for: config)
    try await connectionManager.withConnection { connection in
      let escapedSession = escapeShellArgument(session.value)
      let escapedWindow = escapeShellArgument(window)
      let escapedPath = escapeShellArgument(path)

      let listCommand = "tmux list-windows -t \(escapedSession) -F '#{window_name}' 2>/dev/null || true"
      let windowsList = try await connection.exec(listCommand)
      let names = windowsList
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      if names.contains(where: { $0 == window }) {
        return
      }

      let newWindowCmd = "tmux new-window -t \(escapedSession): -n \(escapedWindow) -c \(escapedPath)"
      do {
        _ = try await connection.exec(newWindowCmd)
        await AppLogger.shared.log(
          "Created tmux window '\(window)' in session '\(session.value)'",
          level: .info,
          category: .workspace
        )
      } catch {
        if case let SSHError.commandFailed(message) = error,
           message.lowercased().contains("duplicate window") || message.lowercased().contains("duplicate") {
          return
        }
        throw error
      }
    }
  }

  func respawnPane(session: TmuxSessionName, window: String, path: String, command: String) async throws {
    let connectionManager = await SSHConnectionPool.shared.manager(for: config)
    try await connectionManager.withConnection { connection in
      let escapedSession = escapeShellArgument(session.value)
      let escapedWindow = escapeShellArgument(window)
      let escapedPath = escapeShellArgument(path)
      let quoted = command.replacingOccurrences(of: "'", with: "'\"'\"'")
      let respawnCmd = "tmux respawn-pane -k -c \(escapedPath) -t \(escapedSession):\(escapedWindow).0 '\(quoted)'"
      _ = try await connection.exec(respawnCmd)
      await AppLogger.shared.log(
        "Respawned tmux pane in '\(session.value):\(window)'",
        level: .info,
        category: .workspace
      )
    }
  }
}
