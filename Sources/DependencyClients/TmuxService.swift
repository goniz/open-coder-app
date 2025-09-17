import Foundation
import Models

struct TmuxService: Sendable {
  private let config: Models.SSHServerConfiguration
  private let sshClient: SSHClient

  init(config: Models.SSHServerConfiguration) {
    self.config = config
    self.sshClient = SSHClient()
  }

  func hasSession(_ name: String) async throws -> Bool {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      return try await connectionManager.withConnection { connection in
        let escapedName = escapeShellArgument(name)
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

  func newSession(name: String, path: String) async throws {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      try await connectionManager.withConnection { connection in
        let escapedName = escapeShellArgument(name)
        let escapedPath = escapeShellArgument(path)
        let command = "tmux new-session -d -s \(escapedName) -c \(escapedPath)"
        do {
          _ = try await connection.exec(command)
          await AppLogger.shared.log(
            "Created tmux session: \(name) at \(path)",
            level: .info,
            category: .workspace
          )
        } catch {
          if case let SSHError.commandFailed(message) = error,
            message.lowercased().contains("duplicate session") {
            await AppLogger.shared.log(
              "Using existing tmux session: \(name)",
              level: .info,
              category: .workspace
            )
            return
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

  func newOrReplaceServerWindow(name: String) async throws {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      try await connectionManager.withConnection { connection in
        let hasExisting = try await hasSession(name)
        if hasExisting {
          let escapedName = escapeShellArgument(name)
          let killCommand = "tmux kill-session -t \(escapedName)"
          _ = try await connection.exec(killCommand)
        }

        let workspacePath = "$HOME"
        try await newSession(name: name, path: workspacePath)
      }
    } catch {
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux server window setup was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  func listSessions() async throws -> [String] {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      return try await connectionManager.withConnection { connection in
        let command = "tmux list-sessions -F '#{session_name}' 2>/dev/null || true"
        let result = try await connection.exec(command)
        return result.split(separator: "\n").map(String.init)
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

  func listWindows(session: String) async throws -> [String] {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      return try await connectionManager.withConnection { connection in
        let escapedSession = escapeShellArgument(session)
        let command =
          "tmux list-windows -t \(escapedSession) -F '#{window_name}' 2>/dev/null || true"
        let result = try await connection.exec(command)
        return result
          .split(separator: "\n")
          .map(String.init)
          .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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

  func killSession(_ name: String) async throws {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      try await connectionManager.withConnection { connection in
        let escapedName = escapeShellArgument(name)
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
  func ensureWindow(session: String, window: String, path: String) async throws {
    let connectionManager = await SSHConnectionPool.shared.manager(for: config)
    try await connectionManager.withConnection { connection in
      let escapedSession = escapeShellArgument(session)
      let escapedWindow = escapeShellArgument(window)
      let escapedPath = escapeShellArgument(path)

      let listCommand = "tmux list-windows -t \(escapedSession) -F '#{window_name}' 2>/dev/null || true"
      let windowsList = try await connection.exec(listCommand)
      let names = windowsList.split(separator: "\n").map(String.init)
      if names.contains(where: { $0 == window }) {
        return
      }

      let newWindowCmd = "tmux new-window -t \(escapedSession): -n \(escapedWindow) -c \(escapedPath)"
      do {
        _ = try await connection.exec(newWindowCmd)
        await AppLogger.shared.log(
          "Created tmux window '\(window)' in session '\(session)'",
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

  func respawnPane(session: String, window: String, path: String, command: String) async throws {
    let connectionManager = await SSHConnectionPool.shared.manager(for: config)
    try await connectionManager.withConnection { connection in
      let escapedSession = escapeShellArgument(session)
      let escapedWindow = escapeShellArgument(window)
      let escapedPath = escapeShellArgument(path)
      let quoted = command.replacingOccurrences(of: "'", with: "'\"'\"'")
      let respawnCmd = "tmux respawn-pane -k -c \(escapedPath) -t \(escapedSession):\(escapedWindow).0 '\(quoted)'"
      _ = try await connection.exec(respawnCmd)
      await AppLogger.shared.log(
        "Respawned tmux pane in '\(session):\(window)'",
        level: .info,
        category: .workspace
      )
    }
  }
}
