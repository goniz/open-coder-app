// swiftlint:disable file_length
import Crypto
import Dependencies
import DependenciesMacros
import Foundation
import Models
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH

// Extension for NSLock to provide a safe locking mechanism
extension NSLock {
  @discardableResult
  func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}

// MARK: - Minimal SFTP client/handler (v3)

private struct SFTPNameEntry: Sendable {
  let filename: String
  let longname: String
  let mode: UInt32?
  let size: UInt64?
  let mtime: UInt32?
}

private enum SFTPReadDirResult: Sendable {
  case names([SFTPNameEntry])
  case eof
}

// swiftlint:disable:next type_body_length
private final class SFTPHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = SSHChannelData

  // SFTP packet types used
  private enum PacketType: UInt8 {
    case initClient = 1
    case version = 2
    case close = 4
    case opendir = 11
    case readdir = 12
    case realpath = 16
    case status = 101
    case handle = 102
    case name = 104
  }

  private struct PendingRequest {
    let promise: EventLoopPromise<(UInt8, ByteBuffer)>
  }

  private let eventLoop: EventLoop
  private var nextRequestId: UInt32 = 1
  private var pending: [UInt32: PendingRequest] = [:]
  private var versionPromise: EventLoopPromise<UInt32>?
  private var inboundBuffer = ByteBuffer()
  private let lock = NSLock()

  init(eventLoop: EventLoop) {
    self.eventLoop = eventLoop
  }

  // MARK: Public API (scheduled on event loop)

  func initialize(on channel: Channel, version: UInt32) async throws -> UInt32 {
    let promise = eventLoop.makePromise(of: UInt32.self)
    self.versionPromise = promise

    var payload = channel.allocator.buffer(capacity: 4)
    payload.writeInteger(version, endianness: .big)
    try await writePacket(on: channel, type: .initClient, requestId: nil, payload: payload)
    return try await promise.futureResult.get()
  }

  func openDirectory(on channel: Channel, path: String) async throws -> ByteBuffer {
    let (reqId, respFuture) = request(on: channel)
    var payload = channel.allocator.buffer(capacity: 4 + path.utf8.count)
    writeString(&payload, path)
    try await writePacket(on: channel, type: .opendir, requestId: reqId, payload: payload)

    let (typeByte, buffer) = try await respFuture.get()
    guard typeByte == PacketType.handle.rawValue else {
      // Attempt to parse status for better error
      if typeByte == PacketType.status.rawValue {
        let (code, msg) = parseStatus(buffer)
        throw SSHError.commandFailed("SFTP OPENDIR failed (code: \(code)): \(msg)")
      }
      throw SSHError.commandFailed("Unexpected SFTP response for OPENDIR: \(typeByte)")
    }
    // Defensive: copy the handle into a fresh buffer so callers don't retain a slice
    var tmp = buffer
    let count = tmp.readableBytes
    var copied = channel.allocator.buffer(capacity: count)
    if let bytes = tmp.readBytes(length: count) {
      copied.writeBytes(bytes)
    }
    return copied
  }

  func realpath(on channel: Channel, path: String) async throws -> String {
    let (reqId, respFuture) = request(on: channel)
    var payload = channel.allocator.buffer(capacity: 4 + path.utf8.count)
    writeString(&payload, path)
    try await writePacket(on: channel, type: .realpath, requestId: reqId, payload: payload)

    let (typeByte, mutBuffer) = try await respFuture.get()
    if typeByte == PacketType.name.rawValue {
      var buf = mutBuffer
      let count: UInt32 = buf.readInteger(endianness: .big) ?? 0
      guard count >= 1 else { throw SSHError.commandFailed("SFTP REALPATH returned no results") }
      guard let filename = readString(&buf) else { throw SSHError.commandFailed("Invalid REALPATH response") }
      // Consume longname and attrs to keep buffer consistent
      _ = readString(&buf) // longname
      var tmpBuf = buf
      _ = parseAttrs(&tmpBuf)
      return filename
    } else if typeByte == PacketType.status.rawValue {
      let (code, message) = parseStatus(mutBuffer)
      throw SSHError.commandFailed("SFTP REALPATH failed (code: \(code)): \(message)")
    } else {
      throw SSHError.commandFailed("Unexpected SFTP response for REALPATH: \(typeByte)")
    }
  }

  func readDirectory(on channel: Channel, handle: ByteBuffer) async throws -> SFTPReadDirResult {
    // The handle returned by OPENDIR is already a full SFTP "string"
    // (uint32 length + bytes). Do not wrap it again.
    let (reqId, respFuture) = request(on: channel)
    let payload = handle
    try await writePacket(on: channel, type: .readdir, requestId: reqId, payload: payload)

    let (typeByte, mutBuffer) = try await respFuture.get()
    if typeByte == PacketType.name.rawValue {
      var buf = mutBuffer
      let count: UInt32 = buf.readInteger(endianness: .big) ?? 0
      var results: [SFTPNameEntry] = []
      results.reserveCapacity(Int(count))
      for _ in 0..<count {
        guard let filename = readString(&buf), let longname = readString(&buf) else { break }
        // Parse attrs to detect dir/size/mtime when available
        let attrs = parseAttrs(&buf)
        results.append(
          SFTPNameEntry(
            filename: filename,
            longname: longname,
            mode: attrs.mode,
            size: attrs.size,
            mtime: attrs.mtime
          )
        )
      }
      return .names(results)
    } else if typeByte == PacketType.status.rawValue {
      let (code, message) = parseStatus(mutBuffer)
      if code == 1 { // SSH_FX_EOF
        return .eof
      }
      throw SSHError.commandFailed("SFTP READDIR failed (code: \(code)): \(message)")
    } else {
      throw SSHError.commandFailed("Unexpected SFTP response for READDIR: \(typeByte)")
    }
  }

  func closeHandle(on channel: Channel, handle: ByteBuffer) async throws {
    // The handle is an SFTP "string" already; send as-is without re-encoding
    let (reqId, respFuture) = request(on: channel)
    let payload = handle
    try await writePacket(on: channel, type: .close, requestId: reqId, payload: payload)
    let (typeByte, buf) = try await respFuture.get()
    guard typeByte == PacketType.status.rawValue else {
      throw SSHError.commandFailed("Unexpected SFTP response for CLOSE: \(typeByte)")
    }
    let (code, msg) = parseStatus(buf)
    if code != 0 {
      throw SSHError.commandFailed("SFTP CLOSE failed (code: \(code)): \(msg)")
    }
  }

  // MARK: ChannelInboundHandler

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let channelData = self.unwrapInboundIn(data)
    guard case .channel = channelData.type, case let .byteBuffer(buf) = channelData.data else {
      return
    }

    // Append to inbound buffer
    if inboundBuffer.readableBytes == 0 {
      inboundBuffer = buf
    } else {
      var tmp = buf
      if let bytes = tmp.readBytes(length: tmp.readableBytes) {
        inboundBuffer.writeBytes(bytes)
      }
    }

    // Parse complete packets
    parsePackets()
  }

  // MARK: Packet parsing and dispatch

  private func parsePackets() {
    while true {
      let savedReaderIndex = inboundBuffer.readerIndex
      guard let packetLength: UInt32 = inboundBuffer.readInteger(endianness: .big) else {
        inboundBuffer.moveReaderIndex(to: savedReaderIndex)
        break
      }
      // Need at least length bytes available
      guard inboundBuffer.readableBytes >= Int(packetLength) else {
        inboundBuffer.moveReaderIndex(to: savedReaderIndex)
        break
      }

      // Read type
      guard let typeByte: UInt8 = inboundBuffer.readInteger() else { break }

      if typeByte == PacketType.version.rawValue {
        // VERSION has: uint32 version, followed by extensions (ignored)
        let version: UInt32 = inboundBuffer.readInteger(endianness: .big) ?? 0
        versionPromise?.succeed(version)
        versionPromise = nil
        // Consume any remaining extension bytes in packet
        if packetLength > 5 { // type(1) + version(4)
          _ = inboundBuffer.readSlice(length: Int(packetLength) - 5)
        }
        continue
      }

      // All other packets: uint32 request-id then payload
      guard let requestId: UInt32 = inboundBuffer.readInteger(endianness: .big) else { break }
      let payloadLength = Int(packetLength) - 1 - 4
      let payload = inboundBuffer.readSlice(length: payloadLength) ?? ByteBuffer()

      // Dispatch to waiting promise
      let entry: PendingRequest? = lock.withLock { pending.removeValue(forKey: requestId) }
      entry?.promise.succeed((typeByte, payload))
    }
  }

  // MARK: Helpers

  private func request(on channel: Channel) -> (UInt32, EventLoopFuture<(UInt8, ByteBuffer)>) {
    let reqId = lock.withLock { () -> UInt32 in
      let id = nextRequestId
      nextRequestId &+= 1
      return id
    }
    let promise = eventLoop.makePromise(of: (UInt8, ByteBuffer).self)
    lock.withLock { pending[reqId] = PendingRequest(promise: promise) }
    return (reqId, promise.futureResult)
  }

  private func writePacket(
    on channel: Channel,
    type: PacketType,
    requestId: UInt32?,
    payload: ByteBuffer
  ) async throws {
    var buffer = channel.allocator.buffer(capacity: 4 + 1 + 4 + payload.readableBytes)
    // length excludes the length field itself
    let bodyLength: Int = 1 + (requestId == nil ? 0 : 4) + payload.readableBytes
    buffer.writeInteger(UInt32(bodyLength), endianness: .big)
    buffer.writeInteger(type.rawValue)
    if let id = requestId { buffer.writeInteger(id, endianness: .big) }
    var payloadCopy = payload
    if let bytes = payloadCopy.readBytes(length: payloadCopy.readableBytes) {
      buffer.writeBytes(bytes)
    }

    try await channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer))).get()
  }

  private func writeString(_ buffer: inout ByteBuffer, _ string: String) {
    let utf8 = Array(string.utf8)
    buffer.writeInteger(UInt32(utf8.count), endianness: .big)
    buffer.writeBytes(utf8)
  }

  private func writeStringBytes(_ buffer: inout ByteBuffer, _ stringBuffer: ByteBuffer) {
    var tmp = stringBuffer
    let count = tmp.readableBytes
    buffer.writeInteger(UInt32(count), endianness: .big)
    if let bytes = tmp.readBytes(length: count) {
      buffer.writeBytes(bytes)
    }
  }

  private func readString(_ buffer: inout ByteBuffer) -> String? {
    guard let len: UInt32 = buffer.readInteger(endianness: .big) else { return nil }
    guard let bytes = buffer.readBytes(length: Int(len)) else { return nil }
    return String(bytes: bytes, encoding: .utf8)
  }

  private func parseStatus(_ buffer: ByteBuffer) -> (code: UInt32, message: String) {
    var buf = buffer
    let code: UInt32 = buf.readInteger(endianness: .big) ?? 255
    let msg = readString(&buf) ?? ""
    // skip language tag
    _ = readString(&buf)
    return (code, msg)
  }

  private struct SFTPAttrs {
    let mode: UInt32?
    let size: UInt64?
    let mtime: UInt32?
  }

  private func parseAttrs(_ buffer: inout ByteBuffer) -> SFTPAttrs {
    guard let flags: UInt32 = buffer.readInteger(endianness: .big) else {
      return SFTPAttrs(mode: nil, size: nil, mtime: nil)
    }
    var mode: UInt32?
    var size: UInt64?
    var mtime: UInt32?
    if (flags & 0x00000001) != 0 { // size
      size = buffer.readInteger(endianness: .big)
    }
    if (flags & 0x00000002) != 0 { // uid/gid
      let _: UInt32? = buffer.readInteger(endianness: .big)
      let _: UInt32? = buffer.readInteger(endianness: .big)
    }
    if (flags & 0x00000004) != 0 { // permissions (mode)
      mode = buffer.readInteger(endianness: .big)
    }
    if (flags & 0x00000008) != 0 { // atime/mtime
      let _: UInt32? = buffer.readInteger(endianness: .big) // atime
      mtime = buffer.readInteger(endianness: .big) // mtime
    }
    // Skip extended attributes if present (rare)
    if (flags & 0x80000000) != 0 {
      let count: UInt32 = buffer.readInteger(endianness: .big) ?? 0
      for _ in 0..<count {
        _ = readString(&buffer)
        _ = readString(&buffer)
      }
    }
    return SFTPAttrs(mode: mode, size: size, mtime: mtime)
  }
}

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

// Helper function to extract detailed error information from NIOSSH errors
private func detailedErrorDescription(_ error: Error) -> String {
  // Map ChannelError to friendly descriptions first
  if let chErr = error as? ChannelError {
    switch chErr {
    case .eof, .inputClosed, .outputClosed, .alreadyClosed:
      return "SSH channel closed by remote host (likely auth failure or network drop)"
    default:
      return "ChannelError: \(chErr)"
    }
  }
  // Try to extract the underlying error from NIOSSH
  let mirror = Mirror(reflecting: error)

  // Look for common NIOSSH error patterns and extract useful information
  let errorString = String(describing: error)

  // If it's a generic NIOSSH error, try to extract more details
  if errorString.contains("NIOSSHError") {
    // Check if we can get more specific error information
    let nsError = error as NSError
    var details = "NIOSSHError (code: \(nsError.code))"
    if !nsError.userInfo.isEmpty {
      let userInfoStr = nsError.userInfo.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
      details += " - \(userInfoStr)"
    }
    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
      details += " - Underlying: \(underlyingError.localizedDescription)"
    }
    return details
  }

  // Try to extract information from the error's mirror reflection
  for (label, value) in mirror.children {
    if let label = label, errorString.contains("NIOSSHError") {
      return "NIOSSHError - \(label): \(value)"
    }
  }

  // Fallback: include the full error type information for SSH errors
  if errorString.contains("NIOSSH") || errorString.contains("SSH") {
    return "\(String(describing: type(of: error))): \(errorString)"
  }

  // For other errors, return the standard description
  return error.localizedDescription
}

// swiftlint:disable:next type_body_length
package struct SSHClient: SSHClientProtocol {
  package init() {}

  package static func testConnection(_ config: Models.SSHServerConfiguration) async throws {
    // Perform a minimal round-trip exec to confirm auth and channel operation
    _ = try await SSHClient().exec("true", config: config)
  }

  package func exec(_ command: String) async throws -> String {
    // This is a simplified implementation that creates a new connection for each command
    // In a production implementation, you would want to reuse connections
    throw SSHError.connectionFailed(
      "exec() requires SSH configuration. Use exec(command:config:) instead."
    )
  }

  // Validate auth intent vs supplied credentials prior to connecting
  private func preflightAuth(_ config: Models.SSHServerConfiguration) throws {
    if config.useKeyAuthentication {
      let trimmed = config.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
      let hasKeyFile = !trimmed.isEmpty && FileManager.default.fileExists(
        atPath: (trimmed as NSString).expandingTildeInPath
      )
      let hasKeyData = (config.privateKeyData != nil)
      if !hasKeyFile && !hasKeyData {
        throw SSHConnectionError.privateKeyPathEmpty
      }
    } else {
      if config.password.isEmpty {
        throw SSHConnectionError.passwordAuthNotAvailable
      }
    }
  }

  // swiftlint:disable:next function_body_length cyclomatic_complexity
  package func exec(_ command: String, config: Models.SSHServerConfiguration) async throws -> String {
    await AppLogger.shared.log("Executing SSH command: \(command)", level: .debug, category: .ssh)
    // Fail fast if configuration cannot possibly authenticate with our supported methods.
    do { try preflightAuth(config) } catch { throw error }
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    var mainChannel: Channel?
    var sessionChannel: Channel?

    do {
      let port = config.port > 0 ? config.port : 22
      let userAuthDelegate = SSHUserAuthDelegate(config: config)
      let serverAuthDelegate = AcceptAllHostKeysDelegate(host: config.host, port: port)

      let bootstrap = ClientBootstrap(group: eventLoopGroup)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
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

      mainChannel = try await bootstrap.connect(host: config.host, port: port).get()

      guard let channel = mainChannel else {
        throw SSHError.connectionFailed("Failed to establish SSH connection")
      }

      // Create a session channel to execute the command
      let sessionPromise = channel.eventLoop.makePromise(of: Channel.self)

      // Create the session via the SSH handler on the event loop
      let creationFuture: EventLoopFuture<Void> = channel.eventLoop.submit {
        let sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
        sshHandler.createChannel(sessionPromise, channelType: .session) { childChannel, _ in
          // Add command output handler to capture stdout/stderr
          let outputHandler = CommandOutputHandler(eventLoop: childChannel.eventLoop, command: command)
          return childChannel.pipeline.addHandler(outputHandler).flatMap { _ in
            Task {
              await AppLogger.shared.log(
                "SSH session channel created and handler attached",
                level: .debug,
                category: .ssh
              )
            }
            return childChannel.eventLoop.makeSucceededFuture(())
          }
        }
      }
      try await creationFuture.get()

      sessionChannel = try await withTimeout(seconds: 15) {
        try await sessionPromise.futureResult.get()
      }

      guard let session = sessionChannel else {
        throw SSHError.connectionFailed("Failed to create SSH session channel")
      }

      guard session.isActive else {
        throw SSHError.connectionFailed("Session channel became inactive before exec request")
      }

      // Now send the exec request after the channel is established
      let execRequest = SSHChannelRequestEvent.ExecRequest(
        command: command,
        wantReply: true
      )
      let noPromise: EventLoopPromise<Void>? = nil
      session.triggerUserOutboundEvent(execRequest, promise: noPromise)
      await AppLogger.shared.log(
        "Command exec request sent: \(command.prefix(100))",
        level: .debug,
        category: .ssh
      )

      // Wait for command execution to complete (timeout after 30 seconds)
      let result = try await withTimeout(seconds: 30) {
        return try await getCommandOutput(from: session)
      }

      // Clean up session channel first, then main channel (best effort; ignore already-closed errors)
      do {
        try await session.close().get()
      } catch {
        await AppLogger.shared.log(
          "Session channel cleanup warning: \(error.localizedDescription)",
          level: .debug,
          category: .ssh
        )
      }
      do {
        try await channel.close().get()
      } catch {
        await AppLogger.shared.log(
          "Main channel cleanup warning: \(error.localizedDescription)",
          level: .debug,
          category: .ssh
        )
      }
      do {
        try await eventLoopGroup.shutdownGracefully()
      } catch {
        await AppLogger.shared.log(
          "EventLoopGroup shutdown warning: \(error.localizedDescription)",
          level: .debug,
          category: .ssh
        )
      }

      await AppLogger.shared.log(
        "SSH command completed successfully", level: .debug, category: .ssh)
      return result
    } catch {
      // Clean up on error
      try? await sessionChannel?.close().get()
      try? await mainChannel?.close().get()
      try? await eventLoopGroup.shutdownGracefully()

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

      // Map channel-closure errors to a clearer message
      if let chErr = error as? ChannelError {
        switch chErr {
        case .eof, .inputClosed, .outputClosed, .alreadyClosed:
          let mapped = SSHError.connectionFailed(
            "SSH channel closed unexpectedly. Verify the server is reachable and your credentials are correct."
          )
          await AppLogger.shared.log(
            "SSH command failed (mapped channel close): \(mapped.localizedDescription)",
            level: .error,
            category: .ssh
          )
          throw mapped
        default:
          break
        }
      }

      await AppLogger.shared.log(
        "SSH command failed: \(detailedErrorDescription(error))", level: .error, category: .ssh)
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
    // Access handler.futureResult on the channel's event loop to avoid syncOperations off-EL
    let future: EventLoopFuture<String> = channel.eventLoop
      .submit {
        let handler = try channel.pipeline.syncOperations.handler(type: CommandOutputHandler.self)
        return handler.completionFuture
      }
      .flatMap { $0 }
    return try await future.get()
  }

  package func execCleanCommand(
    _ baseCommand: String,
    config: Models.SSHServerConfiguration
  ) async throws -> String {
    do {
      // Generate unique markers to isolate command output from bashrc contamination
      let outputMarker = "OPENCODER_START_\(UUID().uuidString.prefix(8))"
      let endMarker = "OPENCODER_END"

      // Properly escape single quotes in the base command for shell execution
      let escapedCommand = baseCommand.replacingOccurrences(of: "'", with: "'\"'\"'")

      // Use sh -c to bypass interactive shell setup (bashrc, bash_profile, etc.)
      // and wrap output with markers for reliable extraction
      let wrappedCommand = """
        sh -c 'echo "\(outputMarker)"; \(escapedCommand); echo "\(endMarker)"'
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

      // No platform-specific CLI fallback; propagate the original error

      throw error
    }
  }

  // MARK: - OpenSSH CLI fallback

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
    var mainChannel: Channel?
    var tcpChannel: Channel?

    do {
      let port = config.port > 0 ? config.port : 22
      let userAuthDelegate = SSHUserAuthDelegate(config: config)
      let serverAuthDelegate = AcceptAllHostKeysDelegate(host: config.host, port: port)

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

      mainChannel = try await bootstrap.connect(host: config.host, port: port).get()

      guard let channel = mainChannel else {
        throw SSHError.connectionFailed("Failed to establish SSH connection")
      }

      // Wait for SSH connection to be established
      try await Task.sleep(nanoseconds: 1_000_000_000)

      // Create a direct TCP/IP channel
      let promise = channel.eventLoop.makePromise(of: Channel.self)

      // Create originator address (localhost:0 for client)
      let originatorAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 0)

      let channelType = SSHChannelType.directTCPIP(
        .init(targetHost: host, targetPort: port, originatorAddress: originatorAddress)
      )

      // Create the channel via the SSH handler on the event loop
      let creationFuture: EventLoopFuture<Void> = channel.eventLoop.submit {
        let sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
        sshHandler.createChannel(promise, channelType: channelType) { childChannel, _ in
          // Set up the channel for direct TCP/IP forwarding
          return childChannel.eventLoop.makeSucceededFuture(())
        }
      }
      try await creationFuture.get()

      tcpChannel = try await promise.futureResult.get()

      // Note: Proper stream handling with the TCP channel needs implementation
      // For now, this is a placeholder implementation
      let inputHandle = FileHandle.nullDevice
      let outputHandle = FileHandle.nullDevice

      // Store references for cleanup closure to avoid capturing mutable variables
      let cleanupChannel = mainChannel
      let cleanupTcpChannel = tcpChannel
      let cleanupEventLoopGroup = eventLoopGroup

      return SSHStream(
        input: inputHandle,
        output: outputHandle,
        close: {
          Task {
            try? await cleanupTcpChannel?.close().get()
            try? await cleanupChannel?.close().get()
            try? await cleanupEventLoopGroup.shutdownGracefully()
          }
        }
      )
    } catch {
      // Clean up resources on error
      try? await tcpChannel?.close().get()
      try? await mainChannel?.close().get()
      try? await eventLoopGroup.shutdownGracefully()

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
        "SSH connection test failed to \(config.host): \(detailedErrorDescription(error))",
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
    await AppLogger.shared.log("Listing directory via SFTP: \(path)", level: .info, category: .fileSystem)
    let files = try await sftpListDirectory(path, config: config)
    await AppLogger.shared.log(
      "SFTP listed \(files.count) items in: \(path)", level: .info, category: .fileSystem)
    return files
  }

  // MARK: - SFTP directory listing

  // Shared helper to open an SFTP session, initialize, run an operation, and clean up
  // swiftlint:disable function_body_length
  private func withSFTP<T: Sendable>(
    config: Models.SSHServerConfiguration,
    operation: @escaping @Sendable (_ channel: Channel, _ handler: SFTPHandler) async throws -> T
  ) async throws -> T {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    var mainChannel: Channel?
    var sessionChannel: Channel?
    do {
      let port = config.port > 0 ? config.port : 22
      let userAuthDelegate = SSHUserAuthDelegate(config: config)
      let serverAuthDelegate = AcceptAllHostKeysDelegate(host: config.host, port: port)

      let bootstrap = ClientBootstrap(group: eventLoopGroup)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
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
          return channel.eventLoop.makeCompletedFuture { try channel.pipeline.syncOperations.addHandler(sshHandler) }
        }

      mainChannel = try await bootstrap.connect(host: config.host, port: port).get()
      guard let channel = mainChannel else { throw SSHError.connectionFailed("Failed to establish SSH connection") }

      try await Task.sleep(nanoseconds: 300_000_000)

      let sessionPromise = channel.eventLoop.makePromise(of: Channel.self)
      // Create the SFTP session channel on the channel's event loop to avoid syncOperations off-EL
      let creationFuture: EventLoopFuture<Void> = channel.eventLoop.submit {
        let sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
        sshHandler.createChannel(sessionPromise, channelType: .session) { childChannel, _ in
          // Add the handler after we obtain the child channel below
          return childChannel.eventLoop.makeSucceededFuture(())
        }
      }
      try await creationFuture.get()

      let sftpChannel: Channel = try await withTimeout(seconds: 15) {
        try await sessionPromise.futureResult.get()
      }
      sessionChannel = sftpChannel

      // Now add our SFTP handler on the child channel's event loop
      let sftpHandler = SFTPHandler(eventLoop: sftpChannel.eventLoop)
      let addFuture: EventLoopFuture<Void> = sftpChannel.eventLoop.submit {
        try sftpChannel.pipeline.syncOperations.addHandler(sftpHandler)
      }
      try await addFuture.get()

      let subsystemRequest = SSHChannelRequestEvent.SubsystemRequest(subsystem: "sftp", wantReply: true)
      let subsystemPromise = sftpChannel.eventLoop.makePromise(of: Void.self)
      sftpChannel.triggerUserOutboundEvent(subsystemRequest, promise: subsystemPromise)
      try await subsystemPromise.futureResult.get()
      _ = try await sftpHandler.initialize(on: sftpChannel, version: 3)

      let result = try await operation(sftpChannel, sftpHandler)

      // Best-effort cleanup; ignore already-closed errors
      do { try await sftpChannel.close().get() } catch {
        await AppLogger.shared.log(
          "SFTP channel cleanup warning: \(error.localizedDescription)",
          level: .debug,
          category: .ssh
        )
      }
      do { try await channel.close().get() } catch {
        await AppLogger.shared.log(
          "Main channel cleanup warning: \(error.localizedDescription)",
          level: .debug,
          category: .ssh
        )
      }
      do { try await eventLoopGroup.shutdownGracefully() } catch {
        await AppLogger.shared.log(
          "EventLoopGroup shutdown warning: \(error.localizedDescription)",
          level: .debug,
          category: .ssh
        )
      }
      return result
    } catch {
      try? await sessionChannel?.close().get()
      try? await mainChannel?.close().get()
      try? await eventLoopGroup.shutdownGracefully()
      throw error
    }
  }
  // swiftlint:enable function_body_length

  private func sftpListDirectory(
    _ path: String,
    config: Models.SSHServerConfiguration
  ) async throws -> [RemoteFileInfo] {
    return try await withSFTP(config: config) { sftpChannel, sftpHandler in
      let handle = try await sftpHandler.openDirectory(on: sftpChannel, path: path)
      let entries = try await sftpReadAllEntries(handler: sftpHandler, channel: sftpChannel, handle: handle)
      try await sftpHandler.closeHandle(on: sftpChannel, handle: handle)

      let files: [RemoteFileInfo] = entries.compactMap { entry in
        if entry.filename == "." || entry.filename == ".." { return nil }
        let fullPath = path.hasSuffix("/") ? "\(path)\(entry.filename)" : "\(path)/\(entry.filename)"
        let isDir: Bool
        if let mode = entry.mode {
          isDir = (mode & 0o170000) == 0o040000
        } else {
          isDir = entry.longname.first == "d"
        }
        let size = entry.size.map { Int64($0) } ?? 0
        let lastModified: Date = entry.mtime.map {
          Date(timeIntervalSince1970: TimeInterval($0))
        } ?? Date(timeIntervalSince1970: 0)
        return RemoteFileInfo(
          name: entry.filename,
          path: fullPath,
          isDirectory: isDir,
          size: size,
          permissions: entry.longname,
          lastModified: lastModified
        )
      }

      return files.sorted { lhs, rhs in
        let dirOrder = (lhs.isDirectory && !rhs.isDirectory)
        let sameType = (lhs.isDirectory == rhs.isDirectory)
        if dirOrder { return true }
        if sameType { return lhs.name.lowercased() < rhs.name.lowercased() }
        return false
      }
    }
  }

  // Resolve a path on the remote using SFTP REALPATH (v3)
  private func sftpResolvePath(
    _ path: String,
    config: Models.SSHServerConfiguration
  ) async throws -> String {
    return try await withSFTP(config: config) { sftpChannel, sftpHandler in
      try await sftpHandler.realpath(on: sftpChannel, path: path)
    }
  }

  private func sftpReadAllEntries(
    handler: SFTPHandler,
    channel: Channel,
    handle: ByteBuffer
  ) async throws -> [SFTPNameEntry] {
    var all: [SFTPNameEntry] = []
    while true {
      let result = try await handler.readDirectory(on: channel, handle: handle)
      switch result {
      case .names(let batch):
        all.append(contentsOf: batch)
      case .eof:
        return all
      }
    }
  }

  // Removed shell fallback for directory listing. All directory operations now use SFTP only.

  package func getRemoteHomeDirectory(config: Models.SSHServerConfiguration) async throws -> String {
    // Prefer SFTP REALPATH-based discovery. Many servers set SFTP CWD to $HOME,
    // so REALPATH on "." is typically the most portable.
    func sanitize(_ path: String) -> String {
      if path.hasSuffix("/~") { return String(path.dropLast(2)) }
      return path
    }

    do {
      // First try realpath(".")
      var resolved = try await sftpResolvePath(".", config: config)
      resolved = sanitize(resolved)
      if !resolved.isEmpty { return resolved }

      // Then try realpath("~") (not standardized, but some servers support it)
      resolved = try await sftpResolvePath("~", config: config)
      resolved = sanitize(resolved)
      if !resolved.isEmpty { return resolved }
    } catch {
      // If SFTP-based discovery fails, fall back to shell-based HOME discovery
      if error is CancellationError {
        throw SSHError.commandFailed(
          "Getting home directory was cancelled. This may be due to network issues or server timeout."
        )
      }
    }

    let result = try await execCleanCommand("echo \"$HOME\"", config: config)
    return result.isEmpty ? "/" : result
  }

  // Removed ls-parsing fallback; SFTP is the single source of directory listings.
}

private final class CommandOutputHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = SSHChannelData

  private var outputBuffer = Data()
  private var errorBuffer = Data()
  private var isComplete = false
  private var receivedExit = false
  private var exitStatusCode: Int32 = -1
  private let completionPromise: EventLoopPromise<String>
  private let command: String

  var completionFuture: EventLoopFuture<String> {
    return completionPromise.futureResult
  }

  init(eventLoop: EventLoop, command: String) {
    self.completionPromise = eventLoop.makePromise(of: String.self)
    self.command = command
    Task {
      await AppLogger.shared.log(
        "CommandOutputHandler initialized for command: \(command.prefix(80))",
        level: .debug,
        category: .ssh
      )
    }
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let channelData = self.unwrapInboundIn(data)

    switch channelData.type {
    case .channel:
      handleStdoutData(channelData.data)
    case .stdErr:
      handleStderrData(channelData.data)
    default:
      Task {
        await AppLogger.shared.log(
          "Received data on unexpected channel type: \(channelData.type)",
          level: .warning,
          category: .ssh
        )
      }
    }
  }

  private func handleStdoutData(_ data: IOData) {
    switch data {
    case .byteBuffer(var buffer):
      if let bytes = buffer.readBytes(length: buffer.readableBytes) {
        let receivedString = String(bytes: bytes, encoding: .utf8) ?? "<non-UTF8 data>"
        Task {
          await AppLogger.shared.log(
            "Received stdout (\(bytes.count) bytes): \(receivedString.prefix(100))",
            level: .debug,
            category: .ssh
          )
        }
        outputBuffer.append(contentsOf: bytes)
      }
    case .fileRegion:
      // File regions aren't expected for command output
      Task {
        await AppLogger.shared.log(
          "Received file region on stdout (unexpected)",
          level: .warning,
          category: .ssh
        )
      }
    }
  }

  private func handleStderrData(_ data: IOData) {
    switch data {
    case .byteBuffer(var buffer):
      if let bytes = buffer.readBytes(length: buffer.readableBytes) {
        let receivedString = String(bytes: bytes, encoding: .utf8) ?? "<non-UTF8 data>"
        Task {
          await AppLogger.shared.log(
            "Received stderr (\(bytes.count) bytes): \(receivedString.prefix(100))",
            level: .debug,
            category: .ssh
          )
        }
        errorBuffer.append(contentsOf: bytes)
      }
    case .fileRegion:
      // File regions aren't expected for command output
      Task {
        await AppLogger.shared.log(
          "Received file region on stderr (unexpected)",
          level: .warning,
          category: .ssh
        )
      }
    }
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    // Log all events for debugging
    let eventType = String(describing: type(of: event))
    Task {
      await AppLogger.shared.log(
        "CommandOutputHandler received event: \(eventType)",
        level: .debug,
        category: .ssh
      )
    }

    // Only handle SSH channel request events that indicate command completion
    if let exitStatusEvent = event as? SSHChannelRequestEvent.ExitStatus {
      handleExitStatus(exitStatusEvent)
    } else if let exitSignal = event as? SSHChannelRequestEvent.ExitSignal {
      handleExitSignal(exitSignal)
    }
    // Note: We don't handle generic ChannelEvent here as it's too broad
    // The channel inactive handler will take care of unexpected closures
  }

  private func handleExitStatus(_ exitStatusEvent: SSHChannelRequestEvent.ExitStatus) {
    // Record status and defer completion until channel closes so we don't race stdout reads.
    receivedExit = true
    exitStatusCode = Int32(exitStatusEvent.exitStatus)
    Task {
      await AppLogger.shared.log(
        "Command exit status received: \(exitStatusEvent.exitStatus)",
        level: .debug,
        category: .ssh
      )
    }
  }

  private func handleExitSignal(_ exitSignal: SSHChannelRequestEvent.ExitSignal) {
    // Treat as failure; we'll finalize on channel close but store state
    receivedExit = true
    exitStatusCode = -1
    Task {
      await AppLogger.shared.log(
        "Command terminated by signal",
        level: .debug,
        category: .ssh
      )
    }
  }

  func waitForOutput() async throws -> String {
    return try await completionPromise.futureResult.get()
  }

  func channelInactive(context: ChannelHandlerContext) {
    let wasComplete = isComplete
    isComplete = true

    if !wasComplete {
      // Finalize based on recorded exit status (if any) and collected buffers.
      isComplete = true
      let output = String(data: outputBuffer, encoding: .utf8) ?? ""
      let errorOutput = String(data: errorBuffer, encoding: .utf8) ?? ""

      if receivedExit {
        if exitStatusCode == 0 {
          completionPromise.succeed(output)
        } else {
          let trimmedCommand = command.count > 200
            ? "\(command.prefix(200))…"
            : command
          let message: String
          if errorOutput.isEmpty {
            message = "`\(trimmedCommand)` failed with exit code \(exitStatusCode)"
          } else {
            message = "`\(trimmedCommand)` failed: \(errorOutput)"
          }
          completionPromise.fail(SSHError.commandFailed(message))
        }
      } else {
        // No exit status observed. Heuristic: prefer stdout, else stderr, else connection failure.
        if !output.isEmpty {
          completionPromise.succeed(output)
        } else if !errorOutput.isEmpty {
          let trimmedCommand = command.count > 200
            ? "\(command.prefix(200))…"
            : command
          let message = "`\(trimmedCommand)` failed: \(errorOutput)"
          completionPromise.fail(SSHError.commandFailed(message))
        } else {
          completionPromise.fail(
            SSHError.connectionFailed(
              "SSH channel closed unexpectedly - the connection may have been terminated by the server"))
        }
      }
    }
  }
}

private final class SSHUserAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
  private let config: Models.SSHServerConfiguration
  private var authenticationAttempts = 0
  private let maxAttempts = 3

  init(config: Models.SSHServerConfiguration) {
    self.config = config
  }

  func nextAuthenticationType(
    availableMethods: NIOSSHAvailableUserAuthenticationMethods,
    nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
  ) {
    // Track authentication attempts
    authenticationAttempts += 1

    if authenticationAttempts > maxAttempts {
      nextChallengePromise.fail(
        SSHConnectionError.keyAuthenticationFailed("Maximum authentication attempts exceeded")
      )
      return
    }

    do {
      if let offer = try chooseAuthenticationOffer(availableMethods: availableMethods) {
        nextChallengePromise.succeed(offer)
      } else {
        // Neither method is possible with current configuration
        if availableMethods.contains(.publicKey) {
          nextChallengePromise.fail(SSHConnectionError.privateKeyPathEmpty)
        } else if availableMethods.contains(.password) {
          nextChallengePromise.fail(SSHConnectionError.passwordAuthNotAvailable)
        } else {
          nextChallengePromise.fail(SSHConnectionError.keyAuthenticationFailed("No supported methods"))
        }
      }
    } catch {
      nextChallengePromise.fail(SSHConnectionError.keyAuthenticationFailed("\(error)"))
    }
  }

  // MARK: - Auth selection helpers

  private func buildPublicKeyOffer(availableMethods: NIOSSHAvailableUserAuthenticationMethods)
    throws -> NIOSSHUserAuthenticationOffer? {
    guard availableMethods.contains(.publicKey) else { return nil }

    // Load Ed25519 private key from raw bytes or OpenSSH unencrypted key file
    let keyData: Data
    if !config.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      FileManager.default.fileExists(atPath: (config.privateKeyPath as NSString).expandingTildeInPath) {
      let expanded = (config.privateKeyPath as NSString).expandingTildeInPath
      let url = URL(fileURLWithPath: expanded)
      keyData = try Data(contentsOf: url)
    } else if let privateKeyData = config.privateKeyData {
      keyData = privateKeyData
    } else {
      // No key material available
      return nil
    }

    let ed25519Seed = try SSHUserAuthDelegate.extractEd25519Seed(from: keyData)
    let edKey = try Curve25519.Signing.PrivateKey(rawRepresentation: ed25519Seed)
    let nioKey = NIOSSHPrivateKey(ed25519Key: edKey)
    Task { await AppLogger.shared.log("Using public key auth", level: .debug, category: .ssh) }
    return NIOSSHUserAuthenticationOffer(
      username: config.username,
      serviceName: "ssh-connection",
      offer: .privateKey(.init(privateKey: nioKey))
    )
  }

  private func buildPasswordOffer(availableMethods: NIOSSHAvailableUserAuthenticationMethods)
    -> NIOSSHUserAuthenticationOffer? {
    guard availableMethods.contains(.password), !config.password.isEmpty else { return nil }
    Task { await AppLogger.shared.log("Using password auth", level: .debug, category: .ssh) }
    return NIOSSHUserAuthenticationOffer(
      username: config.username,
      serviceName: "ssh-connection",
      offer: .password(.init(password: config.password))
    )
  }

  private func chooseAuthenticationOffer(availableMethods: NIOSSHAvailableUserAuthenticationMethods)
    throws -> NIOSSHUserAuthenticationOffer? {
    if config.useKeyAuthentication {
      if let keyOffer = try buildPublicKeyOffer(availableMethods: availableMethods) { return keyOffer }
      if let pwdOffer = buildPasswordOffer(availableMethods: availableMethods) { return pwdOffer }
      return nil
    } else {
      if let pwdOffer = buildPasswordOffer(availableMethods: availableMethods) { return pwdOffer }
      if let keyOffer = try buildPublicKeyOffer(availableMethods: availableMethods) { return keyOffer }
      return nil
    }
  }
}

// MARK: - OpenSSH/Raw key parsing helpers
extension SSHUserAuthDelegate {
  /// Attempts to extract a 32-byte Ed25519 seed from various key formats.
  /// Supported:
  /// - 32-byte raw seed (Curve25519.Signing.PrivateKey rawRepresentation)
  /// - 64-byte concatenation (seed + public key) – uses the first 32 bytes
  /// - OpenSSH unencrypted ed25519 private key (BEGIN OPENSSH PRIVATE KEY)
  ///   with ciphername "none" and kdf "none".
  fileprivate static func extractEd25519Seed(from data: Data) throws -> Data {
    if data.count == 32 { return data }
    if data.count == 64 { return data.prefix(32) }

    // Check for OpenSSH PEM header
    if let text = String(data: data, encoding: .utf8),
      text.contains("BEGIN OPENSSH PRIVATE KEY") {
      return try parseOpenSSHEd25519Seed(fromPEM: text)
    }

    throw SSHConnectionError.keyAuthenticationFailed(
      "Unsupported private key format " +
      "(expected 32/64-byte raw or OpenSSH ed25519 key)"
    )
  }

  /// Parse an unencrypted OpenSSH ed25519 private key (openssh-key-v1) and return the 32-byte seed.
  private static func parseOpenSSHEd25519Seed(fromPEM pem: String) throws -> Data {
    func base64Body(from pem: String) -> Data {
      let lines = pem.split(separator: "\n").map(String.init)
      guard let start = lines.firstIndex(where: { $0.contains("BEGIN OPENSSH PRIVATE KEY") }),
        let end = lines.firstIndex(where: { $0.contains("END OPENSSH PRIVATE KEY") }), end > start else {
        return Data()
      }
      let base64 = lines[(start + 1)..<end].joined()
      return Data(base64Encoded: base64) ?? Data()
    }

    let decodedKeyData = base64Body(from: pem)
    if decodedKeyData.isEmpty {
      throw SSHConnectionError.keyAuthenticationFailed("Invalid OpenSSH key PEM body")
    }

    let privateBlob = try parseOpenSSHPrivateBlob(from: decodedKeyData)
    return try extractEd25519Seed(fromPrivateBlob: privateBlob)
  }

  // Parses the outer OpenSSH key envelope and returns the private key blob.
  private static func parseOpenSSHPrivateBlob(from decodedData: Data) throws -> Data {
    var index = decodedData.startIndex

    func ensureAvailable(_ count: Int) -> Bool {
      return decodedData.distance(from: index, to: decodedData.endIndex) >= count
    }
    func readUInt32() -> UInt32? {
      guard ensureAvailable(4) else { return nil }
      let byte0 = UInt32(decodedData[index])
      let byte1 = UInt32(decodedData[index + 1])
      let byte2 = UInt32(decodedData[index + 2])
      let byte3 = UInt32(decodedData[index + 3])
      index += 4
      return (byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3
    }
    func readStringBytes() -> Data? {
      guard let length = readUInt32() else { return nil }
      let intLength = Int(length)
      guard ensureAvailable(intLength) else { return nil }
      let sub = decodedData[index..<(index + intLength)]
      index += intLength
      return Data(sub)
    }

    // Verify magic bytes: "openssh-key-v1\0"
    let magicBytes = Array("openssh-key-v1\0".utf8)
    guard ensureAvailable(magicBytes.count) else {
      throw SSHConnectionError.keyAuthenticationFailed("OpenSSH key too short")
    }
    let prefix = decodedData[index..<(index + magicBytes.count)]
    guard Array(prefix) == magicBytes else {
      throw SSHConnectionError.keyAuthenticationFailed("Not an OpenSSH v1 key")
    }
    index += magicBytes.count

    // ciphername, kdfname, kdfoptions
    guard let ciphername = readStringBytes(), let kdfname = readStringBytes(), let kdfOptions = readStringBytes() else {
      throw SSHConnectionError.keyAuthenticationFailed("Malformed OpenSSH key header")
    }
    if String(data: ciphername, encoding: .utf8) != "none" || String(data: kdfname, encoding: .utf8) != "none" {
      throw SSHConnectionError.keyAuthenticationFailed("Encrypted OpenSSH keys are not supported")
    }
    _ = kdfOptions // ignored for none

    // number of keys (uint32)
    guard let keyCount = readUInt32(), keyCount == 1 else {
      throw SSHConnectionError.keyAuthenticationFailed("Unexpected key count in OpenSSH key")
    }

    // public key blob (string) - skip
    guard readStringBytes() != nil else {
      throw SSHConnectionError.keyAuthenticationFailed("Missing public key blob")
    }

    // private key blob (string)
    guard let privateBlob = readStringBytes() else {
      throw SSHConnectionError.keyAuthenticationFailed("Missing private key blob")
    }
    return privateBlob
  }

  // Extracts 32-byte ed25519 seed from the private key blob.
  private static func extractEd25519Seed(fromPrivateBlob privateBlobData: Data) throws -> Data {
    let blob = privateBlobData
    var index = blob.startIndex

    func readUInt32() -> UInt32? {
      guard blob.distance(from: index, to: blob.endIndex) >= 4 else { return nil }
      let byte0 = UInt32(blob[index])
      let byte1 = UInt32(blob[index + 1])
      let byte2 = UInt32(blob[index + 2])
      let byte3 = UInt32(blob[index + 3])
      index += 4
      return (byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3
    }
    func readString() -> Data? {
      guard let length = readUInt32() else { return nil }
      let intLength = Int(length)
      guard blob.distance(from: index, to: blob.endIndex) >= intLength else { return nil }
      let sub = blob[index..<(index + intLength)]
      index += intLength
      return Data(sub)
    }

    guard let checkint1 = readUInt32(), let checkint2 = readUInt32(), checkint1 == checkint2 else {
      throw SSHConnectionError.keyAuthenticationFailed("OpenSSH key checkints mismatch")
    }
    guard let keyType = readString(), String(data: keyType, encoding: .utf8) == "ssh-ed25519" else {
      throw SSHConnectionError.keyAuthenticationFailed("Only ed25519 OpenSSH keys are supported")
    }
    guard readString() != nil /* public part */ else {
      throw SSHConnectionError.keyAuthenticationFailed("Malformed OpenSSH private key (pub)")
    }
    guard let privatePart = readString() else {
      throw SSHConnectionError.keyAuthenticationFailed("Malformed OpenSSH private key (priv)")
    }
    // privatePart is 64 bytes: 32 seed + 32 pub
    if privatePart.count >= 32 {
      return privatePart.prefix(32)
    }
    throw SSHConnectionError.keyAuthenticationFailed("Invalid ed25519 private key length in OpenSSH key")
  }
}

private final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked
  Sendable {
  private static let acceptedHostsLock = NSLock()
  nonisolated(unsafe) private static var acceptedHosts = Set<String>()
  private let hostIdentifier: String

  init(host: String = "unknown", port: Int = 22) {
    self.hostIdentifier = "\(host):\(port)"
  }

  init() {
    self.hostIdentifier = "unknown:22"
  }

  func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
    // WARNING: This accepts all host keys without validation
    // In production, you should:
    // 1. Store known host keys and compare
    // 2. Prompt user to accept new keys
    // 3. Detect and warn about changed keys (potential MITM attack)

    // Only log once per host to avoid spam
    let shouldLog = Self.acceptedHostsLock.withLock {
      if !Self.acceptedHosts.contains(hostIdentifier) {
        Self.acceptedHosts.insert(hostIdentifier)
        return true
      }
      return false
    }

    if shouldLog {
      Task {
        await AppLogger.shared.log(
          "Accepting host key for \(hostIdentifier) (fingerprint verification not implemented)",
          level: .debug,
          category: .ssh
        )
      }
    }

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

// MARK: - Connection Management
// MARK: - Connection Management

package actor SSHConnectionManager {
  private let config: Models.SSHServerConfiguration
  private var connection: SSHConnection?

  package init(config: Models.SSHServerConfiguration) {
    self.config = config
  }

  package func isConnected() -> Bool {
    if let connection = self.connection {
      return connection.isHealthy
    }
    return false
  }

  package func withConnection<T>(_ operation: @escaping @Sendable (SSHConnection) async throws -> T) async throws -> T {
    // Check if we have a valid and healthy connection
    if let existingConnection = self.connection, existingConnection.isHealthy {
      do {
        // Try to use the existing connection
        return try await operation(existingConnection)
      } catch {
        // Check if it's a channel closed error (NIOCore.ChannelError error 6)
        let errorString = String(describing: error)
        let isChannelClosedError = errorString.contains("ChannelError") &&
                                  (errorString.contains("error 6") ||
                                   errorString.contains("outputClosed") ||
                                   errorString.contains("inputClosed"))

        if isChannelClosedError {
          await AppLogger.shared.log(
            "SSH channel closed unexpectedly, will create new connection",
            level: .warning,
            category: .ssh
          )
        } else {
          await AppLogger.shared.log(
            "Existing connection failed, will create new one: \(detailedErrorDescription(error))",
            level: .debug,
            category: .ssh
          )
        }

        await existingConnection.close()
        self.connection = nil
      }
    }

    // Create new connection with retry logic
    return try await withRetry(maxRetries: 3, baseDelay: 1.0) { [self] in
      if self.connection == nil || !self.connection!.isHealthy {
        await AppLogger.shared.log("Creating new SSH connection", level: .debug, category: .ssh)
        self.connection = try await self.createConnection()

        // Add a small delay to ensure the connection is fully ready
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
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
          "retrying in \(delay)s: \(detailedErrorDescription(error))",
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
    var channel: Channel?

    do {
      let port = config.port > 0 ? config.port : 22
      let userAuthDelegate = SSHUserAuthDelegate(config: config)
      let serverAuthDelegate = AcceptAllHostKeysDelegate(host: config.host, port: port)

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

      // Port already declared above, just use it
      channel = try await bootstrap.connect(host: config.host, port: port).get()

      guard let establishedChannel = channel else {
        throw SSHError.connectionFailed("Failed to establish channel")
      }

      // Wait for SSH connection to be established and verify it's ready
      try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

      // Verify the connection is actually established by checking channel state
      guard establishedChannel.isActive else {
        throw SSHError.connectionFailed("Channel not active after connection")
      }

      await AppLogger.shared.log(
        "SSH connection established successfully to \(config.host):\(port)",
        level: .debug,
        category: .ssh
      )

      return SSHConnection(channel: establishedChannel, eventLoopGroup: eventLoopGroup)
    } catch {
      // Ensure cleanup happens on error
      if let channel = channel {
        try? await channel.close().get()
      }
      try? await eventLoopGroup.shutdownGracefully()
      throw error
    }
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

  /// Check if the channel is healthy and ready for operations
  var isHealthy: Bool {
    // Consider a channel healthy if it's active; writability may briefly be false due to backpressure
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
    // Ensure the connection is healthy before executing
    guard isHealthy else {
      throw SSHError.connectionFailed("SSH connection is not healthy - channel is inactive or closing")
    }

    // Create a session channel to execute the command
    let sessionPromise = channel.eventLoop.makePromise(of: Channel.self)

    // Create the session via the SSH handler on the event loop
    let creationFuture: EventLoopFuture<Void> = channel.eventLoop.submit {
      let sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
      sshHandler.createChannel(sessionPromise, channelType: .session) { childChannel, _ in
      // Add command output handler to capture stdout/stderr
      let outputHandler = CommandOutputHandler(eventLoop: childChannel.eventLoop, command: command)
      return childChannel.pipeline.addHandler(outputHandler).flatMap { _ in
        // Signal that channel is ready
        Task {
          await AppLogger.shared.log(
            "SSH session channel created via connection pool and handler attached",
            level: .debug,
            category: .ssh
          )
        }
        return childChannel.eventLoop.makeSucceededFuture(())
      }
    }
    }
    try await creationFuture.get()

    let sessionChannel = try await sessionPromise.futureResult.get()

    guard sessionChannel.isActive else {
      throw SSHError.connectionFailed("Session channel inactive before exec request")
    }

    // Now send the exec request after the channel is established
    let execRequest = SSHChannelRequestEvent.ExecRequest(
      command: command,
      wantReply: true
    )
    let noPromise: EventLoopPromise<Void>? = nil
    sessionChannel.triggerUserOutboundEvent(execRequest, promise: noPromise)
    await AppLogger.shared.log(
      "Command exec request sent via connection pool: \(command.prefix(100))",
      level: .debug,
      category: .ssh
    )

    // Wait for command execution to complete (timeout after 30 seconds)
    let result = try await withTimeout(seconds: 30) {
      return try await getCommandOutput(from: sessionChannel)
    }

    // Clean up session channel gracefully
    do {
      try await sessionChannel.close().get()
    } catch {
      // Log but don't fail - channel might already be closed
      await AppLogger.shared.log(
        "Session channel cleanup warning: \(error.localizedDescription)",
        level: .debug,
        category: .ssh
      )
    }

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
    let future: EventLoopFuture<String> = channel.eventLoop
      .submit {
        let handler = try channel.pipeline.syncOperations.handler(type: CommandOutputHandler.self)
        return handler.completionFuture
      }
      .flatMap { $0 }
    return try await future.get()
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
