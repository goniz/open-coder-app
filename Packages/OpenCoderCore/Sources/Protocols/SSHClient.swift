import Foundation
import Models

public protocol SSHClientProtocol: Sendable {
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

public struct SSHPTYSession {
  public let stdin: FileHandle
  public let stdout: FileHandle
  public let stderr: FileHandle
  public let processId: Int32
  
  public init(stdin: FileHandle, stdout: FileHandle, stderr: FileHandle, processId: Int32) {
    self.stdin = stdin
    self.stdout = stdout
    self.stderr = stderr
    self.processId = processId
  }
}

public struct SSHStream {
  public let input: FileHandle
  public let output: FileHandle
  public let close: () -> Void
  
  public init(input: FileHandle, output: FileHandle, close: @escaping () -> Void) {
    self.input = input
    self.output = output
    self.close = close
  }
}

public struct RemoteFileInfo: Equatable, Identifiable, Sendable {
  public let id = UUID()
  public let name: String
  public let path: String
  public let isDirectory: Bool
  public let size: Int64
  public let permissions: String
  public let lastModified: Date

  public init(
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

public enum SSHError: LocalizedError, Equatable, Sendable {
  case connectionFailed(String)
  case authenticationFailed(String)
  case commandFailed(String)
  case fingerprintMismatch(String)
  case portCollision(String)
  case spawnTimeout(String)
  case staleLock(String)

  public var errorDescription: String? {
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

public enum SSHConnectionError: LocalizedError, Sendable {
  case publicKeyAuthNotAvailable
  case passwordAuthNotAvailable
  case privateKeyPathEmpty
  case keyAuthenticationFailed(String)

  public var errorDescription: String? {
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