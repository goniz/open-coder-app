import Foundation
import Models
import NIOCore
import NIOPosix
import NIOSSH

package struct SSHClient {
  package static func testConnection(_ config: SSHServerConfiguration) async throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      try? eventLoopGroup.syncShutdownGracefully()
    }
    
    let bootstrap = ClientBootstrap(group: eventLoopGroup)
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelInitializer { channel in
        let userAuthDelegate = SSHUserAuthDelegate(config: config)
        let sshHandler = NIOSSHHandler(
          role: .client(.init(userAuthDelegate: userAuthDelegate, serverHostKeyValidator: AcceptAllHostKeysDelegate())),
          allocator: channel.allocator
        )
        return channel.pipeline.addHandler(sshHandler)
      }
    
    let port = config.port > 0 ? config.port : 22
    let channel = try await bootstrap.connect(host: config.host, port: port).get()
    defer {
      try? channel.close().wait()
    }
    
    // Wait a bit for connection establishment and auth
    try await Task.sleep(nanoseconds: 2_000_000_000)
  }
}

private final class SSHUserAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
  private let config: SSHServerConfiguration
  
  init(config: SSHServerConfiguration) {
    self.config = config
  }
  
  func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
    if config.useKeyAuthentication {
      if availableMethods.contains(.publicKey) {
        do {
          let privateKey = try NIOSSHPrivateKey(pemRepresentation: loadPrivateKey())
          let offer = NIOSSHUserAuthenticationOffer(username: config.username, serviceName: "", offer: .privateKey(.init(privateKey: privateKey)))
          nextChallengePromise.succeed(offer)
        } catch {
          nextChallengePromise.fail(SSHConnectionError.keyAuthenticationFailed(error.localizedDescription))
        }
      } else {
        nextChallengePromise.fail(SSHConnectionError.publicKeyAuthNotAvailable)
      }
    } else {
      if availableMethods.contains(.password) {
        let offer = NIOSSHUserAuthenticationOffer(username: config.username, serviceName: "", offer: .password(.init(password: config.password)))
        nextChallengePromise.succeed(offer)
      } else {
        nextChallengePromise.fail(SSHConnectionError.passwordAuthNotAvailable)
      }
    }
  }
  
  private func loadPrivateKey() throws -> String {
    guard !config.privateKeyPath.isEmpty else {
      throw SSHConnectionError.privateKeyPathEmpty
    }
    
    let keyPath: String
    if config.privateKeyPath.hasPrefix("~/") {
      keyPath = NSString(string: config.privateKeyPath).expandingTildeInPath
    } else {
      keyPath = config.privateKeyPath
    }
    
    return try String(contentsOfFile: keyPath, encoding: .utf8)
  }
}

private final class AcceptAllHostKeysDelegate: NIOSSHClientServerHostKeyValidator {
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