// swiftlint:disable file_length

import Foundation
import Models
import NIOCore
@preconcurrency import NIOSSH
import Protocols

public struct WorkspaceService: Sendable {
  private let config: Models.SSHServerConfiguration
  private let tmuxService: TmuxService
  private let sshClient: SSHClient

  public init(config: Models.SSHServerConfiguration) {
    self.config = config
    self.sshClient = SSHClient()
    self.tmuxService = TmuxService(config: config)
  }

  public struct SpawnResult: Equatable, Sendable {
    public let port: Int
    public let online: Bool
    public let error: SSHError?

    public init(port: Int, online: Bool, error: SSHError?) {
      self.port = port
      self.online = online
      self.error = error
    }
  }

  public func connectAndEnsureTmux(workspace: Models.Workspace) async throws {
    await AppLogger.shared.log(
      "Connecting and ensuring tmux session for: \(workspace.name)",
      level: .info,
      category: .workspace
    )

    _ = try await tmuxService.newSession(name: workspace.tmuxSession, path: workspace.remotePath)
  }

  // swiftlint:disable:next function_body_length
  public func attachOrSpawn(workspace: Models.Workspace) async throws -> SpawnResult {
    do {
      await AppLogger.shared.log(
        "Attaching or spawning for workspace: \(workspace.name)",
        level: .info,
        category: .workspace
      )

      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      return try await connectionManager.withConnection { connection in
        try await tmuxService.newSession(name: workspace.tmuxSession, path: workspace.remotePath)

        if let daemonData = try await readDaemonData(workspace: workspace, connection: connection),
          let port = daemonData["port"],
          await healthCheck(port: port, workspace: workspace) {
          await AppLogger.shared.log(
            "Workspace already online on port \(port) - reusing session",
            level: .info,
            category: .workspace
          )
          return SpawnResult(port: port, online: true, error: nil)
        }

        let opencodeCommand = "opencode serve --hostname 127.0.0.1 --port 0 --print-logs"
        let runDir = workspace.remotePath
        let stateDirectory = workspaceStateDirectory(for: workspace)
        let logPath = workspaceLogPath(for: workspace)
        let daemonPath = workspaceDaemonPath(for: workspace)
        let spawnScript = """
          set -euo pipefail
          state_dir=\(stateDirectory.escapingDoubleQuotes())
          lock_dir="$state_dir/lock.d"
          log_file=\(logPath.escapingDoubleQuotes())
          run_dir=\(runDir.escapingDoubleQuotes())

          mkdir -p "$state_dir"

          cleanup_lock() {
            if [ -d "$lock_dir" ]; then
              rmdir "$lock_dir" 2>/dev/null || true
            fi
          }

          if mkdir "$lock_dir" 2>/dev/null; then
            trap cleanup_lock EXIT INT TERM HUP
            cd "$run_dir"
            \(opencodeCommand) | tee -a "$log_file"
          else
            printf '[Live Output] Another opencode launch is already in progress.\\n'
            exit 0
          fi
          """

        let spawnCommand = "bash -lc \(escapeShellArgument(spawnScript))"

        await AppLogger.shared.log(
          "Spawning opencode server with script:\n\(spawnScript)",
          level: .info,
          category: .workspace
        )

        try await tmuxService.ensureWindow(
          session: workspace.tmuxSession,
          window: "opencode",
          path: workspace.remotePath
        )

        try await tmuxService.respawnPane(
          session: workspace.tmuxSession,
          window: "opencode",
          path: workspace.remotePath,
          command: spawnCommand
        )

        let maxRetries = 30
        for _ in 0..<maxRetries {
          if let assignedPort = try await parsePortFromLogs(
            workspace: workspace, connection: connection) {
            let daemonData = try JSONEncoder().encode(["port": assignedPort])
            if let daemonJson = String(data: daemonData, encoding: .utf8) {
              let writeCommand =
                "mkdir -p \(stateDirectory) && echo '\(daemonJson)' > \(daemonPath)"
              _ = try await connection.exec(writeCommand)
            }

            if await healthCheck(port: assignedPort, workspace: workspace) {
              await AppLogger.shared.log(
                "OpenCode server started successfully on port \(assignedPort)",
                level: .info,
                category: .workspace
              )
              return SpawnResult(port: assignedPort, online: true, error: nil)
            }
          }
          try await Task.sleep(for: .seconds(1))
        }

        await AppLogger.shared.log(
          "Failed to start opencode server within timeout for workspace: \(workspace.name)",
          level: .error,
          category: .workspace
        )
        let timeoutError = SSHError.spawnTimeout("Failed to start opencode server within timeout")
        return SpawnResult(port: 0, online: false, error: timeoutError)
      }
    } catch {
      if error is CancellationError {
        let cancellationError = SSHError.spawnTimeout(
          "Workspace spawn was cancelled. This may be due to network issues or server timeout.")
        await AppLogger.shared.log(
          "Workspace spawn cancelled for: \(workspace.name)",
          level: .error,
          category: .workspace
        )
        return SpawnResult(port: 0, online: false, error: cancellationError)
      }

      throw error
    }
  }

  public func listTmuxWindows(workspace: Models.Workspace) async throws -> [String] {
    try await tmuxService.listWindows(session: workspace.tmuxSession)
  }

  // swiftlint:disable function_body_length
  public func getLiveOutputStream(workspace: Models.Workspace, window: String? = nil)
    -> AsyncStream<String> {
    AsyncStream { continuation in
      Task {
        do {
          if let window {
            do {
              let snapshot = try await tmuxService.paneSnapshot(
                session: workspace.tmuxSession,
                window: window,
                lineCount: 200
              )
              snapshot.forEach { continuation.yield($0) }
            } catch {
              continuation.yield(
                "[Live Output] Failed to capture tmux output: \(error.localizedDescription)"
              )
            }
          }

          let manager = await SSHConnectionPool.shared.manager(for: self.config)
          try await manager.withConnection { connection in
            let command: String

            if let window {
              command = tmuxService.paneStreamingCommand(
                session: workspace.tmuxSession,
                window: window
              )
            } else {
              let logPath = workspaceLogPath(for: workspace)
              command = "tail -n 200 -F \(logPath) 2>/dev/null"
            }

            let sessionPromise = connection.channel.eventLoop.makePromise(of: Channel.self)
            let creationFuture: EventLoopFuture<Void> = connection.channel.eventLoop.submit {
              let sshHandler = try connection.channel.pipeline.syncOperations.handler(
                type: NIOSSHHandler.self)
              sshHandler.createChannel(sessionPromise, channelType: .session) { child, _ in
                let handler = LineStreamHandler(
                  onLine: { continuation.yield($0) },
                  onErrorLine: { continuation.yield($0) },
                  onFinish: { _ in continuation.finish() }
                )
                return child.pipeline.addHandler(handler)
    }
  }
  // swiftlint:enable function_body_length
            try await creationFuture.get()
            let streamChannel = try await sessionPromise.futureResult.get()

            let exec = SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
            let noPromise: EventLoopPromise<Void>? = nil
            streamChannel.triggerUserOutboundEvent(exec, promise: noPromise)

            continuation.onTermination = { _ in
              Task { try? await streamChannel.close().get() }
            }
          }
        } catch {
          continuation.finish()
        }
      }
    }
  }

  public func cleanAndRetry(workspace: Models.Workspace) async throws -> SpawnResult {
    do {
      let connectionManager = await SSHConnectionPool.shared.manager(for: config)
      try await connectionManager.withConnection { connection in
        let stateDirectory = workspaceStateDirectory(for: workspace)
        let daemonPath = workspaceDaemonPath(for: workspace)
        let logPath = workspaceLogPath(for: workspace)
        let cleanupCommand = "rm -f \(daemonPath) \(logPath); rm -rf \(stateDirectory)/lock.d"
        _ = try await connection.exec(cleanupCommand)
        try await tmuxService.killSession(workspace.tmuxSession)
      }

      return try await attachOrSpawn(workspace: workspace)
    } catch {
      if error is CancellationError {
        let cancellationError = SSHError.spawnTimeout(
          "Workspace cleanup and retry was cancelled. This may be due to network issues or server timeout."
        )
        await AppLogger.shared.log(
          "Workspace cleanup cancelled for: \(workspace.name)",
          level: .error,
          category: .workspace
        )
        return SpawnResult(port: 0, online: false, error: cancellationError)
      }

      throw error
    }
  }
}

extension WorkspaceService {
  fileprivate func workspaceStateDirectory(for workspace: Models.Workspace) -> String {
    "$HOME/.opencoder/workspaces/\(workspace.id.uuidString)"
  }

  fileprivate func workspaceDaemonPath(for workspace: Models.Workspace) -> String {
    "\(workspaceStateDirectory(for: workspace))/daemon.json"
  }

  fileprivate func workspaceLogPath(for workspace: Models.Workspace) -> String {
    "\(workspaceStateDirectory(for: workspace))/live.log"
  }

  fileprivate func readDaemonData(workspace: Models.Workspace, connection: SSHConnection)
    async throws -> [String: Int]? {
    let daemonPath = workspaceDaemonPath(for: workspace)
    let escapedDaemonPath = daemonPath.escapingDoubleQuotes()
    let command = """
      if [ -f "\(escapedDaemonPath)" ]; then
        cat "\(escapedDaemonPath)" 2>/dev/null
      else
        printf ''
      fi
      """
    let output = try await connection.exec(command)
    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedOutput.isEmpty else { return nil }
    guard let data = trimmedOutput.data(using: .utf8) else { return nil }
    return try JSONDecoder().decode([String: Int].self, from: data)
  }

  fileprivate func parsePortFromLogs(workspace: Models.Workspace, connection: SSHConnection)
    async throws -> Int? {
    let logPath = workspaceLogPath(for: workspace)
    let command = "tail -n 50 \(logPath) 2>/dev/null || echo ''"
    let logContent = try await connection.exec(command)
    let pattern =
      #"(?i)(opencode|opencode\s*ai|opencode-ai).*server listening on http://[^:]+:(\d+)"#

    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
      let match = regex.firstMatch(
        in: logContent, range: NSRange(logContent.startIndex..., in: logContent)),
      let portRange = Range(match.range(at: 2), in: logContent) {
      let portString = String(logContent[portRange])
      if let port = Int(portString) {
        return port
      }
    }

    return nil
  }

  fileprivate func healthCheck(port: Int, workspace: Models.Workspace) async -> Bool {
    port > 0
  }
}

private final class LineStreamHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = SSHChannelData

  private var stdoutBuffer = Data()
  private var stderrBuffer = Data()
  private var finished = false
  private let onLine: @Sendable (String) -> Void
  private let onErrorLine: @Sendable (String) -> Void
  private let onFinish: @Sendable ((any Swift.Error)?) -> Void

  init(
    onLine: @escaping @Sendable (String) -> Void,
    onErrorLine: @escaping @Sendable (String) -> Void,
    onFinish: @escaping @Sendable ((any Swift.Error)?) -> Void
  ) {
    self.onLine = onLine
    self.onErrorLine = onErrorLine
    self.onFinish = onFinish
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let channelData = self.unwrapInboundIn(data)
    switch channelData.type {
    case .channel:
      if case .byteBuffer(var buf) = channelData.data,
        let bytes = buf.readBytes(length: buf.readableBytes) {
        stdoutBuffer.append(contentsOf: bytes)
        flushLines(buffer: &stdoutBuffer, emit: onLine)
      }
    case .stdErr:
      if case .byteBuffer(var buf) = channelData.data,
        let bytes = buf.readBytes(length: buf.readableBytes) {
        stderrBuffer.append(contentsOf: bytes)
        flushLines(buffer: &stderrBuffer, emit: onErrorLine)
      }
    default:
      break
    }
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if let exitStatus = event as? SSHChannelRequestEvent.ExitStatus {
      if !finished {
        finished = true
        if exitStatus.exitStatus == 0 {
          flushRemainder()
          onFinish(nil)
        } else {
          let err: any Swift.Error = SSHError.commandFailed(
            "Command finished with exit code: \(exitStatus.exitStatus)")
          onFinish(err)
        }
      }
    } else if event is SSHChannelRequestEvent.ExitSignal {
      if !finished {
        finished = true
        flushRemainder()
        onFinish(SSHError.commandFailed("Command terminated by signal") as any Swift.Error)
      }
    }
  }

  func channelInactive(context: ChannelHandlerContext) {
    if !finished {
      finished = true
      flushRemainder()
      onFinish(nil)
    }
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    if !finished {
      finished = true
      flushRemainder()
      onFinish(error)
    }
  }

  private func flushLines(buffer: inout Data, emit: @Sendable (String) -> Void) {
    while let range = buffer.firstRange(of: Data([UInt8(10)])) {
      let lineData = buffer[..<range.lowerBound]
      if let line = String(data: lineData, encoding: .utf8) {
        emit(line)
      }
      buffer.removeSubrange(..<range.upperBound)
    }
  }

  private func flushRemainder() {
    if !stdoutBuffer.isEmpty, let line = String(data: stdoutBuffer, encoding: .utf8) {
      onLine(line)
      stdoutBuffer.removeAll()
    }
    if !stderrBuffer.isEmpty, let line = String(data: stderrBuffer, encoding: .utf8) {
      onErrorLine(line)
      stderrBuffer.removeAll()
    }
  }
}

extension String {
  fileprivate func escapingDoubleQuotes() -> String {
    replacingOccurrences(of: "\"", with: "\\\"")
  }
}
