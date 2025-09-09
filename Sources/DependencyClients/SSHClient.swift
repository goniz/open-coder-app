import Foundation
import Models
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH
import Crypto

package struct SSHClient {
  package static func testConnection(_ config: Models.SSHServerConfiguration) async throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    do {
      let bootstrap = ClientBootstrap(group: eventLoopGroup)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .channelInitializer { channel in
          let userAuthDelegate = SSHUserAuthDelegate(config: config)
          let sshHandler = NIOSSHHandler(
            role: .client(.init(userAuthDelegate: userAuthDelegate, serverAuthDelegate: AcceptAllHostKeysDelegate())),
            allocator: channel.allocator,
            inboundChildChannelInitializer: nil
          )
          // NIOSSHHandler's Sendable conformance is explicitly unavailable by design
          // This usage is safe within the EventLoop's single-threaded context
          return channel.pipeline.addHandler(sshHandler)
        }

      let port = config.port > 0 ? config.port : 22
      let channel = try await bootstrap.connect(host: config.host, port: port).get()

      do {
        // Wait a bit for connection establishment and auth
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await channel.close()
      } catch {
        try? await channel.close()
        throw error
      }

      try await eventLoopGroup.shutdownGracefully()
    } catch {
      try await eventLoopGroup.shutdownGracefully()
      throw error
    }
  }
}

private final class SSHUserAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
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

private final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
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
