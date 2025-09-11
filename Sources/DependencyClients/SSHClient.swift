// swiftlint:disable file_length
import Crypto
import Dependencies
import DependenciesMacros
import Foundation
import Models
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH

package protocol SSHClientProtocol: Sendable {
  func exec(_ command: String) async throws -> String
  func exec(_ command: String, config: Models.SSHServerConfiguration) async throws -> String
  func openPTY(_ command: String) async throws -> SSHPTYSession
  func openDirectTCPIP(host: String, port: Int) async throws -> SSHStream
  func openDirectTCPIP(
    host: String,
    port: Int,
    config: Models.SSHServerConfiguration
  ) async throws -> SSHStream
  func testConnection(_ config: Models.SSHServerConfiguration) async throws
  func connect(_ config: Models.SSHServerConfiguration) async throws
  func disconnect() async throws
  func listDirectory(_ path: String, config: Models.SSHServerConfiguration) async throws
    -> [RemoteFileInfo]
  func getRemoteHomeDirectory(config: Models.SSHServerConfiguration) async throws -> String
}

package struct SSHPTYSession {
  let stdin: FileHandle
  let stdout: FileHandle
  let stderr: FileHandle
  let processId: Int32
}

package struct SSHStream {
  let input: FileHandle
  let output: FileHandle
  let close: () -> Void
}

package struct RemoteFileInfo: Equatable, Identifiable {
  package let id = UUID()
  package let name: String
  package let path: String
  package let isDirectory: Bool
  package let size: Int64
  package let permissions: String
  package let lastModified: Date

  package init(
    name: String,
    path: String,
    isDirectory: Bool,
    size: Int64 = 0,
    permissions: String = "",
    lastModified: Date = Date()
  ) {
    self.name = name
    self.path = path
    self.isDirectory = isDirectory
    self.size = size
    self.permissions = permissions
    self.lastModified = lastModified
  }
}

package enum SSHError: LocalizedError, Equatable {
  case connectionFailed(String)
  case authenticationFailed(String)
  case commandFailed(String)
  case fingerprintMismatch(String)
  case portCollision(String)
  case spawnTimeout(String)
  case staleLock(String)

  package var errorDescription: String? {
    switch self {
    case .connectionFailed(let message):
      return "SSH connection failed: \(message)"
    case .authenticationFailed(let message):
      return "Authentication failed: \(message)"
    case .commandFailed(let message):
      return "Command failed: \(message)"
    case .fingerprintMismatch(let message):
      return "Host fingerprint mismatch: \(message)"
    case .portCollision(let message):
      return "Port collision: \(message)"
    case .spawnTimeout(let message):
      return "Spawn timeout: \(message)"
    case .staleLock(let message):
      return "Stale lock detected: \(message)"
    }
  }
}

// swiftlint:disable:next type_body_length
package struct SSHClient: SSHClientProtocol {
  package init() {}

  package static func testConnection(_ config: Models.SSHServerConfiguration) async throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    do {
      let bootstrap = ClientBootstrap(group: eventLoopGroup)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .channelInitializer { channel in
          let userAuthDelegate = SSHUserAuthDelegate(config: config)
          let sshHandler = NIOSSHHandler(
            role: .client(
              .init(
                userAuthDelegate: userAuthDelegate,
                serverAuthDelegate: AcceptAllHostKeysDelegate()
              )),
            allocator: channel.allocator,
            inboundChildChannelInitializer: nil
          )
          // Use the official Apple pattern from NIOSSHServer example to avoid Sendable conformance issues
          return channel.eventLoop.makeCompletedFuture {
            try channel.pipeline.syncOperations.addHandler(sshHandler)
          }
        }

      let port = config.port > 0 ? config.port : 22
      let channel = try await bootstrap.connect(host: config.host, port: port).get()

      do {
        // Wait a bit for connection establishment and auth
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await channel.close()
      } catch {
        try? await channel.close()

        // Handle CancellationError specifically
        if error is CancellationError {
          throw SSHError.connectionFailed(
            "SSH connection test was cancelled. This may be due to network issues or server timeout."
          )
        }

        throw error
      }

      try await eventLoopGroup.shutdownGracefully()
    } catch {
      try await eventLoopGroup.shutdownGracefully()

      // Handle CancellationError at the top level too
      if error is CancellationError {
        throw SSHError.connectionFailed(
          "SSH connection test was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  package func exec(_ command: String) async throws -> String {
    // This is a simplified implementation that creates a new connection for each command
    // In a production implementation, you would want to reuse connections
    throw SSHError.connectionFailed(
      "exec() requires SSH configuration. Use exec(command:config:) instead."
    )
  }

  // swiftlint:disable:next function_body_length
  package func exec(_ command: String, config: Models.SSHServerConfiguration) async throws -> String {
    await AppLogger.shared.log("Executing SSH command: \(command)", level: .debug, category: .ssh)
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    do {
      let userAuthDelegate = SSHUserAuthDelegate(config: config)
      let serverAuthDelegate = AcceptAllHostKeysDelegate()

      let bootstrap = ClientBootstrap(group: eventLoopGroup)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .channelInitializer { channel in
          let sshHandler = NIOSSHHandler(
            role: .client(
              .init(
                userAuthDelegate: userAuthDelegate,
                serverAuthDelegate: serverAuthDelegate
              )),
            allocator: channel.allocator,
            inboundChildChannelInitializer: nil
          )
          return channel.eventLoop.makeCompletedFuture {
            try channel.pipeline.syncOperations.addHandler(sshHandler)
          }
        }

      let port = config.port > 0 ? config.port : 22
      let channel = try await bootstrap.connect(host: config.host, port: port).get()

      // Wait for SSH connection to be established
      try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

      // Create a session channel to execute the command
      let sessionPromise = channel.eventLoop.makePromise(of: Channel.self)

      // Get the SSH handler from the main channel
      let sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)

      sshHandler.createChannel(sessionPromise, channelType: .session) { childChannel, _ in
        // Add command output handler to capture stdout/stderr
        let outputHandler = CommandOutputHandler(eventLoop: childChannel.eventLoop)
        return childChannel.pipeline.addHandler(outputHandler).flatMap { _ in
          // Execute the command
          let execRequest = SSHChannelRequestEvent.ExecRequest(
            command: command,
            wantReply: true
          )

          let execPromise = childChannel.eventLoop.makePromise(of: Void.self)
          childChannel.triggerUserOutboundEvent(
            execRequest,
            promise: execPromise
          )

          return execPromise.futureResult.map { _ in
            // Return success - output will be handled by the handler
            ()
          }
        }
      }

      let sessionChannel = try await sessionPromise.futureResult.get()

      // Wait for command execution to complete (timeout after 30 seconds)
      let result = try await withTimeout(seconds: 30) {
        return try await getCommandOutput(from: sessionChannel)
      }

      // Clean up in reverse order to avoid channel errors
      try await channel.close().get()        // Close main channel first
      try await sessionChannel.close().get() // Then session channel
      try await eventLoopGroup.shutdownGracefully()

      await AppLogger.shared.log(
        "SSH command completed successfully", level: .debug, category: .ssh)
      return result
    } catch {
      try await eventLoopGroup.shutdownGracefully()

      // Handle CancellationError specifically and convert to meaningful SSH error
      if error is CancellationError {
        let cancellationError = SSHError.commandFailed(
          "SSH operation was cancelled. This may be due to network issues, server timeout, or taking too long."
        )
        await AppLogger.shared.log(
          "SSH command cancelled: \(cancellationError.localizedDescription)", level: .error,
          category: .ssh
        )
        throw cancellationError
      }

      await AppLogger.shared.log(
        "SSH command failed: \(error.localizedDescription)", level: .error, category: .ssh)
      throw error
    }
  }

  private func withTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }

      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        throw SSHError.commandFailed("Command execution timeout")
      }

      guard let result = try await group.next() else {
        throw SSHError.commandFailed("No result from command execution")
      }

      group.cancelAll()
      return result
    }
  }

  private func getCommandOutput(from channel: Channel) async throws -> String {
    // Try to get the output handler from the channel pipeline
    if let outputHandler = try? channel.pipeline.syncOperations.handler(
      type: CommandOutputHandler.self) {
      return try await outputHandler.waitForOutput()
    } else {
      throw SSHError.commandFailed("Output handler not found in channel pipeline")
    }
  }

  package func execCleanCommand(
    _ baseCommand: String,
    config: Models.SSHServerConfiguration
  ) async throws -> String {
    do {
      // Generate unique markers to isolate command output from bashrc contamination
      let outputMarker = "OPENCODER_START_\(UUID().uuidString.prefix(8))"
      let endMarker = "OPENCODER_END"

      // Use sh -c to bypass interactive shell setup (bashrc, bash_profile, etc.)
      // and wrap output with markers for reliable extraction
      let wrappedCommand = """
        sh -c 'echo "\(outputMarker)"; \(baseCommand); echo "\(endMarker)"'
        """

      let rawOutput = try await exec(wrappedCommand, config: config)
      return extractCleanOutput(from: rawOutput, startMarker: outputMarker, endMarker: endMarker)
    } catch {
      // Handle CancellationError specifically
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Clean command execution was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  package func extractCleanOutput(from output: String, startMarker: String, endMarker: String)
    -> String {
    let lines = output.components(separatedBy: .newlines)
    var capturing = false
    var cleanLines: [String] = []

    for line in lines {
      if line.contains(startMarker) {
        capturing = true
        continue
      }
      if line.contains(endMarker) {
        break
      }
      if capturing {
        cleanLines.append(line)
      }
    }

    return cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  package func openPTY(_ command: String) async throws -> SSHPTYSession {
    // Implementation would open a PTY session
    throw SSHError.connectionFailed("PTY not implemented in mock")
  }

  package func openDirectTCPIP(host: String, port: Int) async throws -> SSHStream {
    // Implementation would open direct TCP/IP channel
    throw SSHError.connectionFailed("Direct TCP/IP not implemented in mock")
  }

  // swiftlint:disable:next function_body_length
  package func openDirectTCPIP(
    host: String,
    port: Int,
    config: Models.SSHServerConfiguration
  ) async throws -> SSHStream {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    do {
      let userAuthDelegate = SSHUserAuthDelegate(config: config)
      let serverAuthDelegate = AcceptAllHostKeysDelegate()

      let bootstrap = ClientBootstrap(group: eventLoopGroup)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .channelInitializer { channel in
          let sshHandler = NIOSSHHandler(
            role: .client(
              .init(
                userAuthDelegate: userAuthDelegate,
                serverAuthDelegate: serverAuthDelegate
              )),
            allocator: channel.allocator,
            inboundChildChannelInitializer: nil
          )
          return channel.eventLoop.makeCompletedFuture {
            try channel.pipeline.syncOperations.addHandler(sshHandler)
          }
        }

      let sshPort = config.port > 0 ? config.port : 22
      let channel = try await bootstrap.connect(host: config.host, port: sshPort).get()

      // Create a direct TCP/IP channel
      let promise = eventLoopGroup.next().makePromise(of: Channel.self)

      // Create originator address (localhost:0 for client)
      let originatorAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 0)

      let channelType = SSHChannelType.directTCPIP(
        .init(targetHost: host, targetPort: port, originatorAddress: originatorAddress)
      )

      let sshHandler = NIOSSHHandler(
        role: .client(
          .init(
            userAuthDelegate: userAuthDelegate,
            serverAuthDelegate: serverAuthDelegate
          )),
        allocator: channel.allocator,
        inboundChildChannelInitializer: nil
      )

      sshHandler.createChannel(promise, channelType: channelType) { channel, _ in
        // Set up the channel for direct TCP/IP forwarding
        return channel.eventLoop.makeSucceededFuture(())
      }

      _ = try await promise.futureResult.get()

      // For now, return mock file handles
      let inputHandle = FileHandle(forReadingAtPath: "/dev/null") ?? FileHandle.nullDevice
      let outputHandle = FileHandle(forWritingAtPath: "/dev/null") ?? FileHandle.nullDevice

      // Clean up
      // try await channel.close().get()
      // try await eventLoopGroup.shutdownGracefully()

      return SSHStream(
        input: inputHandle,
        output: outputHandle,
        close: {
          // In a real implementation, this would close the channel properly
        }
      )
    } catch {
      // Handle CancellationError specifically
      if error is CancellationError {
        throw SSHError.connectionFailed(
          "SSH direct TCP/IP connection was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  package func testConnection(_ config: Models.SSHServerConfiguration) async throws {
    await AppLogger.shared.log(
      "Testing SSH connection to \(config.host):\(config.port)", level: .info, category: .ssh)
    do {
      try await SSHClient.testConnection(config)
      await AppLogger.shared.log(
        "SSH connection test successful to \(config.host)", level: .info, category: .ssh)
    } catch {
      // Handle CancellationError specifically
      if error is CancellationError {
        let cancellationError = SSHError.connectionFailed(
          "SSH connection test was cancelled. This may be due to network issues or server timeout.")
        await AppLogger.shared.log(
          "SSH connection test cancelled to \(config.host): \(cancellationError.localizedDescription)",
          level: .error,
          category: .ssh
        )
        throw cancellationError
      }

      await AppLogger.shared.log(
        "SSH connection test failed to \(config.host): \(error.localizedDescription)",
        level: .error,
        category: .ssh
      )
      throw error
    }
  }

  package func connect(_ config: Models.SSHServerConfiguration) async throws {
    try await testConnection(config)
  }

  package func disconnect() async throws {
    // Mock implementation
  }

  package func listDirectory(_ path: String, config: Models.SSHServerConfiguration) async throws
    -> [RemoteFileInfo] {
    await AppLogger.shared.log("Listing directory: \(path)", level: .info, category: .fileSystem)

    do {
      // Use clean execution to avoid bashrc contamination in ls output
      let result = try await execCleanCommand("ls -la '\(path)' 2>/dev/null", config: config)

      if result.isEmpty {
        await AppLogger.shared.log(
          "Cannot access directory: \(path)", level: .error, category: .fileSystem)
        throw SSHError.commandFailed("Cannot access directory: \(path)")
      }

      let files = parseDirectoryListing(result, basePath: path)
      await AppLogger.shared.log(
        "Found \(files.count) items in directory: \(path)", level: .info, category: .fileSystem)
      return files
    } catch {
      // Handle CancellationError specifically
      if error is CancellationError {
        let cancellationError = SSHError.commandFailed(
          "Directory listing was cancelled. This may be due to network issues or server timeout.")
        await AppLogger.shared.log(
          "Directory listing cancelled for path: \(path)", level: .error, category: .fileSystem)
        throw cancellationError
      }

      throw error
    }
  }

  package func getRemoteHomeDirectory(config: Models.SSHServerConfiguration) async throws -> String {
    do {
      // Use clean execution to avoid bashrc contamination
      let result = try await execCleanCommand("echo \"$HOME\"", config: config)

      // Fallback to root if HOME is empty (shouldn't happen but safety first)
      return result.isEmpty ? "/" : result
    } catch {
      // Handle CancellationError specifically
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Getting home directory was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  private func parseDirectoryListing(_ output: String, basePath: String) -> [RemoteFileInfo] {
    let lines = output.components(separatedBy: .newlines)
    var files: [RemoteFileInfo] = []

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty || trimmed.hasPrefix("total ") {
        continue
      }

      let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
      if components.count >= 9 {
        let permissions = components[0]
        let isDirectory = permissions.hasPrefix("d")
        let size = Int64(components[4]) ?? 0
        let fileName = components[8..<components.count].joined(separator: " ")

        if fileName == "." || fileName == ".." {
          continue
        }

        let fullPath =
          basePath.hasSuffix("/") ? "\(basePath)\(fileName)" : "\(basePath)/\(fileName)"

        let fileInfo = RemoteFileInfo(
          name: fileName,
          path: fullPath,
          isDirectory: isDirectory,
          size: size,
          permissions: permissions
        )
        files.append(fileInfo)
      }
    }

    return files.sorted {
      $0.isDirectory && !$1.isDirectory
        || ($0.isDirectory == $1.isDirectory && $0.name.lowercased() < $1.name.lowercased())
    }
  }
}

private final class CommandOutputHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = SSHChannelData

  private var outputBuffer = Data()
  private var errorBuffer = Data()
  private var isComplete = false
  private let completionPromise: EventLoopPromise<String>

  var completionFuture: EventLoopFuture<String> {
    return completionPromise.futureResult
  }

  init(eventLoop: EventLoop) {
    self.completionPromise = eventLoop.makePromise(of: String.self)
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let channelData = self.unwrapInboundIn(data)

    switch channelData.type {
    case .channel:
      // Standard output
      switch channelData.data {
      case .byteBuffer(var buffer):
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
          outputBuffer.append(contentsOf: bytes)
        }
      case .fileRegion:
        // File regions aren't expected for command output
        break
      }
    case .stdErr:
      // Standard error
      switch channelData.data {
      case .byteBuffer(var buffer):
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
          errorBuffer.append(contentsOf: bytes)
        }
      case .fileRegion:
        // File regions aren't expected for command output
        break
      }
    default:
      break
    }
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if let exitStatusEvent = event as? SSHChannelRequestEvent.ExitStatus {
      if exitStatusEvent.exitStatus == 0 {
        // Command completed successfully
        let output = String(data: outputBuffer, encoding: .utf8) ?? ""
        completionPromise.succeed(output)
      } else {
        // Command failed
        let errorOutput =
          String(data: errorBuffer, encoding: .utf8)
          ?? "Command failed with exit code \(exitStatusEvent.exitStatus)"
        completionPromise.fail(SSHError.commandFailed(errorOutput))
      }
      isComplete = true
    } else if event is ChannelEvent {
      // Handle channel close events
      if !isComplete {
        let output = String(data: outputBuffer, encoding: .utf8) ?? ""
        if !output.isEmpty {
          completionPromise.succeed(output)
        } else {
          let errorOutput = String(data: errorBuffer, encoding: .utf8) ?? "No output received"
          completionPromise.fail(SSHError.commandFailed(errorOutput))
        }
        isComplete = true
      }
    }
  }

  func waitForOutput() async throws -> String {
    return try await completionPromise.futureResult.get()
  }

  func channelInactive(context: ChannelHandlerContext) {
    if !isComplete {
      let output = String(data: outputBuffer, encoding: .utf8) ?? ""
      if !output.isEmpty {
        completionPromise.succeed(output)
      } else {
        completionPromise.fail(
          SSHError.connectionFailed("Channel closed before command completion"))
      }
      isComplete = true
    }
  }
}

private final class SSHUserAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
  private let config: Models.SSHServerConfiguration

  init(config: Models.SSHServerConfiguration) {
    self.config = config
  }

  func nextAuthenticationType(
    availableMethods: NIOSSHAvailableUserAuthenticationMethods,
    nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
  ) {
    if config.useKeyAuthentication {
      // Key authentication is not fully implemented yet
      nextChallengePromise.fail(
        SSHConnectionError.keyAuthenticationFailed(
          "Key authentication is not yet implemented. Please use password authentication."
        )
      )
    } else {
      if availableMethods.contains(.password) {
        let offer = NIOSSHUserAuthenticationOffer(
          username: config.username,
          serviceName: "",
          offer: .password(.init(password: config.password))
        )
        nextChallengePromise.succeed(offer)
      } else {
        nextChallengePromise.fail(SSHConnectionError.passwordAuthNotAvailable)
      }
    }
  }
}

private final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked
  Sendable {
  func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
    // For demo purposes, accept all host keys
    // In production, you should implement proper host key validation
    validationCompletePromise.succeed(())
  }
}

package enum SSHConnectionError: Error, LocalizedError {
  case publicKeyAuthNotAvailable
  case passwordAuthNotAvailable
  case privateKeyPathEmpty
  case keyAuthenticationFailed(String)

  package var errorDescription: String? {
    switch self {
    case .publicKeyAuthNotAvailable:
      return "Public key authentication is not available on the server"
    case .passwordAuthNotAvailable:
      return "Password authentication is not available on the server"
    case .privateKeyPathEmpty:
      return "Private key path is required for key authentication"
    case .keyAuthenticationFailed(let reason):
      return "Key authentication failed: \(reason)"
    }
  }
}

struct TmuxService: Sendable {
  private let config: Models.SSHServerConfiguration
  private let sshClient: SSHClient
  private let connectionManager: SSHConnectionManager

  init(config: Models.SSHServerConfiguration) {
    self.config = config
    self.sshClient = SSHClient()
    self.connectionManager = SSHConnectionManager(config: config)
  }

  func hasSession(_ name: String) async throws -> Bool {
    do {
      return try await connectionManager.withConnection { connection in
        let command = "tmux has-session -t \(name) 2>/dev/null && echo 'exists' || echo 'not found'"
        let result = try await connection.exec(command)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "exists"
      }
    } catch {
      // Handle CancellationError specifically
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux session check was cancelled. This may be due to network issues or server timeout.")
      }

      throw error
    }
  }

  func newSession(name: String, path: String) async throws {
    do {
      try await connectionManager.withConnection { connection in
        let command = "tmux new-session -d -s \(name) -c \(path)"
        _ = try await connection.exec(command)
      }
    } catch {
      // Handle CancellationError specifically
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
      try await connectionManager.withConnection { connection in
        let hasExisting = try await hasSession(name)
        if hasExisting {
          let killCommand = "tmux kill-session -t \(name)"
          _ = try await connection.exec(killCommand)
        }

        let workspacePath = "$HOME"
        try await newSession(name: name, path: workspacePath)
      }
    } catch {
      // Handle CancellationError specifically
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
      return try await connectionManager.withConnection { connection in
        let command = "tmux list-sessions -F '#{session_name}' 2>/dev/null || true"
        let result = try await connection.exec(command)
        return result.split(separator: "\n").map(String.init)
      }
    } catch {
      // Handle CancellationError specifically
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux session listing was cancelled. This may be due to network issues or server timeout."
        )
      }

      throw error
    }
  }

  func killSession(_ name: String) async throws {
    do {
      try await connectionManager.withConnection { connection in
        let command = "tmux kill-session -t \(name) 2>/dev/null || true"
        _ = try await connection.exec(command)
      }
    } catch {
      // Handle CancellationError specifically
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Tmux session kill was cancelled. This may be due to network issues or server timeout.")
      }

      throw error
    }
  }
}

package struct WorkspaceService: Sendable {
  private let config: Models.SSHServerConfiguration
  private let tmuxService: TmuxService
  private let sshClient: SSHClient
  private let connectionManager: SSHConnectionManager

  package init(config: Models.SSHServerConfiguration) {
    self.config = config
    self.sshClient = SSHClient()
    self.tmuxService = TmuxService(config: config)
    self.connectionManager = SSHConnectionManager(config: config)
  }

  package struct SpawnResult: Equatable {
    package let port: Int
    package let online: Bool
    package let error: SSHError?
  }

  // swiftlint:disable:next function_body_length
  package func attachOrSpawn(workspace: Models.Workspace) async throws -> SpawnResult {
    await AppLogger.shared.log(
      "Attaching or spawning workspace: \(workspace.name)", level: .info, category: .workspace)

    do {
      // Use connection manager for all SSH operations to reuse the same connection
      return try await connectionManager.withConnection { connection in
        // Step 1: Ensure tmux session exists
        let sessionExists = try await tmuxService.hasSession(workspace.tmuxSession)
        if !sessionExists {
          await AppLogger.shared.log(
            "Creating new tmux session: \(workspace.tmuxSession)",
            level: .info,
            category: .workspace
          )
          try await tmuxService.newSession(name: workspace.tmuxSession, path: workspace.remotePath)
        } else {
          await AppLogger.shared.log(
            "Using existing tmux session: \(workspace.tmuxSession)",
            level: .info,
            category: .workspace
          )
        }

        // Step 2: Check for existing daemon.json using the same connection
        let checkCommand = """
          test -f \(workspace.remotePath)/.opencode/daemon.json && \
          cat \(workspace.remotePath)/.opencode/daemon.json || echo '{}'
          """
        let daemonContent = try await connection.exec(checkCommand)

        // Parse daemon.json to check for existing port
        let decoder = JSONDecoder()
        if let data = daemonContent.data(using: .utf8),
          let daemonInfo = try? decoder.decode([String: Int].self, from: data),
          let existingPort = daemonInfo["port"] {

          // Health probe existing port
          await AppLogger.shared.log(
            "Found existing daemon on port \(existingPort), checking health",
            level: .info,
            category: .workspace
          )
          if await healthCheck(port: existingPort, workspace: workspace) {
            await AppLogger.shared.log(
              "Existing daemon is healthy on port \(existingPort)",
              level: .info,
              category: .workspace
            )
            return SpawnResult(port: existingPort, online: true, error: nil)
          } else {
            await AppLogger.shared.log(
              "Existing daemon is unhealthy on port \(existingPort), will spawn new instance",
              level: .warning,
              category: .workspace
            )
          }
        }

        // Step 3: Spawn opencode server with automatic port selection
        await AppLogger.shared.log(
          "Spawning opencode server for workspace: \(workspace.name)",
          level: .info,
          category: .workspace
        )
        let spawnCommand = """
          opencode serve --hostname 127.0.0.1 --port 0 --print-logs | \
          tee -a \(workspace.remotePath)/.opencode/live.log
          """

        // Execute spawn command in tmux window using the same connection
        let tmuxCommand = "tmux send-keys -t \(workspace.tmuxSession):0 '\(spawnCommand)' C-m"
        _ = try await connection.exec(tmuxCommand)

        // Step 4: Wait for server to start and parse the assigned port from logs
        let maxRetries = 30  // 30 seconds timeout
        for _ in 0..<maxRetries {
          if let assignedPort = try await parsePortFromLogs(workspace: workspace, connection: connection) {
            // Create daemon.json with the actual assigned port
            let daemonData = try JSONEncoder().encode(["port": assignedPort])
            if let daemonJson = String(data: daemonData, encoding: .utf8) {
              let writeCommand = """
                mkdir -p \(workspace.remotePath)/.opencode && \
                echo '\(daemonJson)' > \(workspace.remotePath)/.opencode/daemon.json
                """
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
      // Handle CancellationError specifically
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

  private func parsePortFromLogs(workspace: Models.Workspace, connection: SSHConnection) async throws -> Int? {
    do {
      // Read the live log to find the assigned port using the existing connection
      let logPath = "\(workspace.remotePath)/.opencode/live.log"
      let command = "tail -n 50 \(logPath) 2>/dev/null || echo ''"
      let logContent = try await connection.exec(command)

      // Look for opencode server startup pattern: "opencode server listening on http://127.0.0.1:51535"
      let pattern = #"opencode server listening on http://[^:]+:(\d+)"#

      if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
        let match = regex.firstMatch(
          in: logContent, range: NSRange(logContent.startIndex..., in: logContent)),
        let portRange = Range(match.range(at: 1), in: logContent) {
        let portString = String(logContent[portRange])
        if let port = Int(portString) {
          return port
        }
      }

      return nil
    } catch {
      // Handle CancellationError specifically - don't throw, just return nil
      if error is CancellationError {
        await AppLogger.shared.log(
          "Port parsing was cancelled for workspace: \(workspace.name)",
          level: .warning,
          category: .workspace
        )
        return nil
      }

      throw error
    }
  }

  private func healthCheck(port: Int, workspace: Models.Workspace) async -> Bool {
    // Mock health check - in real implementation would probe the server
    return port > 0
  }

  func getLiveOutputStream(workspace: Models.Workspace) -> AsyncStream<String> {
    return AsyncStream { continuation in
      Task {
        do {
          let tailCommand = "tail -n 200 -F \(workspace.remotePath)/.opencode/live.log"
          let result = try await self.sshClient.exec(tailCommand, config: self.config)

          let lines = result.split(separator: "\n")
          for line in lines {
            continuation.yield(String(line))
          }

          continuation.finish()
        } catch {
          continuation.finish()
        }
      }
    }
  }

  package func cleanAndRetry(workspace: Models.Workspace) async throws -> SpawnResult {
    do {
      // Use connection manager for cleanup operations too
      try await connectionManager.withConnection { connection in
        // Remove stale daemon.json and lock files
        let cleanupCommand = """
          rm -f \(workspace.remotePath)/.opencode/daemon.json \(workspace.remotePath)/.opencode/lock
          """
        _ = try await connection.exec(cleanupCommand)

        // Kill existing tmux session
        try await tmuxService.killSession(workspace.tmuxSession)
      }

      // Retry spawn
      return try await attachOrSpawn(workspace: workspace)
    } catch {
      // Handle CancellationError specifically
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

// MARK: - Connection Management

package actor SSHConnectionManager {
  private let config: Models.SSHServerConfiguration
  private var connection: SSHConnection?

  package init(config: Models.SSHServerConfiguration) {
    self.config = config
  }

  package func withConnection<T>(_ operation: @escaping @Sendable (SSHConnection) async throws -> T) async throws -> T {
    return try await withRetry(maxRetries: 3, baseDelay: 1.0) { [self] in
      if self.connection == nil || !self.connection!.isActive {
        await AppLogger.shared.log("Creating new SSH connection", level: .debug, category: .ssh)
        self.connection = try await self.createConnection()
      }

      return try await operation(self.connection!)
    }
  }

  private func withRetry<T>(
    maxRetries: Int,
    baseDelay: TimeInterval,
    operation: @escaping () async throws -> T
  ) async throws -> T {
    var lastError: Error?

    for attempt in 0...maxRetries {
      do {
        return try await operation()
      } catch {
        lastError = error

        // Don't retry on the last attempt
        if attempt == maxRetries {
          break
        }

        // Calculate exponential backoff delay
        let delay = baseDelay * pow(2.0, Double(attempt))
        await AppLogger.shared.log(
          "SSH operation failed (attempt \(attempt + 1)/\(maxRetries + 1)), " +
          "retrying in \(delay)s: \(error.localizedDescription)",
          level: .warning,
          category: .ssh
        )

        // Reset connection on error to force reconnection
        if let connection = self.connection {
          await connection.close()
          self.connection = nil
        }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
    }

    throw lastError ?? SSHError.connectionFailed("Operation failed after \(maxRetries + 1) attempts")
  }

  private func createConnection() async throws -> SSHConnection {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let userAuthDelegate = SSHUserAuthDelegate(config: config)
    let serverAuthDelegate = AcceptAllHostKeysDelegate()

    let bootstrap = ClientBootstrap(group: eventLoopGroup)
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelInitializer { channel in
        let sshHandler = NIOSSHHandler(
          role: .client(
            .init(
              userAuthDelegate: userAuthDelegate,
              serverAuthDelegate: serverAuthDelegate
            )),
          allocator: channel.allocator,
          inboundChildChannelInitializer: nil
        )
        return channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.addHandler(sshHandler)
        }
      }

    let port = config.port > 0 ? config.port : 22
    let channel = try await bootstrap.connect(host: config.host, port: port).get()

    // Wait for SSH connection to be established
    try await Task.sleep(nanoseconds: 1_000_000_000)

    return SSHConnection(channel: channel, eventLoopGroup: eventLoopGroup)
  }

  package func disconnect() async {
    if let connection = connection {
      await connection.close()
      self.connection = nil
    }
  }
}

package struct SSHConnection: Sendable {
  let channel: Channel
  let eventLoopGroup: EventLoopGroup

  var isActive: Bool {
    channel.isActive
  }

  func close() async {
    do {
      try await channel.close().get()
      try await eventLoopGroup.shutdownGracefully()
    } catch {
      // Log but don't throw - cleanup should be best effort
    }
  }

  func exec(_ command: String) async throws -> String {
    // Create a session channel to execute the command
    let sessionPromise = channel.eventLoop.makePromise(of: Channel.self)

    // Get the SSH handler from the main channel
    let sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)

    sshHandler.createChannel(sessionPromise, channelType: .session) { childChannel, _ in
      // Add command output handler to capture stdout/stderr
      let outputHandler = CommandOutputHandler(eventLoop: childChannel.eventLoop)
      return childChannel.pipeline.addHandler(outputHandler).flatMap { _ in
        // Execute the command
        let execRequest = SSHChannelRequestEvent.ExecRequest(
          command: command,
          wantReply: true
        )

        let execPromise = childChannel.eventLoop.makePromise(of: Void.self)
        childChannel.triggerUserOutboundEvent(
          execRequest,
          promise: execPromise
        )

        return execPromise.futureResult.map { _ in
          // Return success - output will be handled by the handler
          ()
        }
      }
    }

    let sessionChannel = try await sessionPromise.futureResult.get()

    // Wait for command execution to complete (timeout after 30 seconds)
    let result = try await withTimeout(seconds: 30) {
      return try await getCommandOutput(from: sessionChannel)
    }

    // Clean up session channel only
    try await sessionChannel.close().get()

    return result
  }

  private func withTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }

      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        throw SSHError.commandFailed("Command execution timeout")
      }

      guard let result = try await group.next() else {
        throw SSHError.commandFailed("No result from command execution")
      }

      group.cancelAll()
      return result
    }
  }

  private func getCommandOutput(from channel: Channel) async throws -> String {
    // Try to get the output handler from the channel pipeline
    if let outputHandler = try? channel.pipeline.syncOperations.handler(
      type: CommandOutputHandler.self) {
      return try await outputHandler.waitForOutput()
    } else {
      throw SSHError.commandFailed("Output handler not found in channel pipeline")
    }
  }
}

// MARK: - Dependency Injection

extension SSHClient: TestDependencyKey {
  package static let testValue = Self()
}

extension DependencyValues {
  package var sshClient: SSHClient {
    get { self[SSHClient.self] }
    set { self[SSHClient.self] = newValue }
  }
}
