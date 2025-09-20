import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import Models

package struct LivePortForwardingClient: PortForwardingClient {
  private let manager = PortForwardListenerManager()

  package init() {}

  package func startForward(
    workspace _: Workspace,
    serverConfig: Models.SSHServerConfiguration,
    remotePort: Int
  ) async throws -> PortForwardToken {
    try await manager.startForward(serverConfig: serverConfig, remotePort: remotePort)
  }

  package func stopForward(_ token: PortForwardToken) async {
    await manager.stopForward(token)
  }
}

private actor PortForwardListenerManager {
  private struct Handle {
    let group: EventLoopGroup
    let channel: Channel
    let serverConfig: Models.SSHServerConfiguration
    let token: PortForwardToken
  }

  private var handles: [UUID: Handle] = [:]

  func startForward(serverConfig: Models.SSHServerConfiguration, remotePort: Int) async throws
    -> PortForwardToken {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 16)
      .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .childChannelInitializer { channel in
        self.configureChildChannel(
          channel: channel,
          serverConfig: serverConfig,
          remotePort: remotePort
        )
      }
      .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)

    let serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
    guard let localPort = serverChannel.localAddress?.port else {
      try await serverChannel.close().get()
      try await group.shutdownGracefully()
      throw SSHError.connectionFailed("Failed to determine local listening address for port forwarding")
    }

    let token = PortForwardToken(localPort: localPort, remotePort: remotePort)
    handles[token.id] = Handle(group: group, channel: serverChannel, serverConfig: serverConfig, token: token)
    return token
  }

  func stopForward(_ token: PortForwardToken) async {
    guard let handle = handles.removeValue(forKey: token.id) else { return }
    do {
      try await handle.channel.close().get()
      try await handle.group.shutdownGracefully()
    } catch {
      // Best-effort shutdown
    }
  }

  nonisolated private func configureChildChannel(
    channel: Channel,
    serverConfig: Models.SSHServerConfiguration,
    remotePort: Int
  ) -> EventLoopFuture<Void> {
    let promise = channel.eventLoop.makePromise(of: Void.self)

    Task {
      do {
        let connectionManager = await SSHConnectionPool.shared.manager(for: serverConfig)
        let remoteChannel = try await connectionManager.withConnection { connection -> Channel in
          try await connection.createDirectTCPIPChannel(
            targetHost: "127.0.0.1",
            targetPort: remotePort,
            configurePipeline: { childChannel in
              childChannel.pipeline.addHandler(SSHDirectTCPIPHandler(peer: channel))
            }
          )
        }

        try await channel.eventLoop.flatSubmit {
          channel.pipeline.addHandler(LocalForwardHandler(peer: remoteChannel))
        }.get()

        channel.closeFuture.whenComplete { _ in
          remoteChannel.eventLoop.execute {
            remoteChannel.close(promise: nil)
          }
        }

        remoteChannel.closeFuture.whenComplete { _ in
          channel.eventLoop.execute {
            channel.close(promise: nil)
          }
        }

        promise.succeed(())
      } catch {
        channel.eventLoop.execute {
          channel.close(promise: nil)
        }
        promise.fail(error)
      }
    }

    return promise.futureResult
  }
}

private final class LocalForwardHandler: ChannelDuplexHandler, @unchecked Sendable {
  typealias InboundIn = ByteBuffer
  typealias OutboundIn = ByteBuffer
  typealias OutboundOut = ByteBuffer

  private let peer: Channel

  init(peer: Channel) {
    self.peer = peer
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var buffer = unwrapInboundIn(data)
    let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
    guard !bytes.isEmpty else { return }
    let peer = self.peer
    peer.eventLoop.execute {
      var peerBuffer = peer.allocator.buffer(capacity: bytes.count)
      peerBuffer.writeBytes(bytes)
      peer.writeAndFlush(peerBuffer, promise: nil)
    }
  }

  func channelInactive(context: ChannelHandlerContext) {
    let peer = self.peer
    peer.eventLoop.execute {
      peer.close(promise: nil)
    }
    context.fireChannelInactive()
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    let peer = self.peer
    peer.eventLoop.execute {
      peer.close(promise: nil)
    }
    context.close(promise: nil)
  }
}

private final class SSHDirectTCPIPHandler: ChannelDuplexHandler, @unchecked Sendable {
  typealias InboundIn = SSHChannelData
  typealias OutboundIn = ByteBuffer
  typealias OutboundOut = SSHChannelData

  private let peer: Channel

  init(peer: Channel) {
    self.peer = peer
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let sshData = unwrapInboundIn(data)
    guard sshData.type == .channel else { return }

    switch sshData.data {
    case .byteBuffer(var buffer):
      let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
      guard !bytes.isEmpty else { return }
      let peer = self.peer
      peer.eventLoop.execute {
        var peerBuffer = peer.allocator.buffer(capacity: bytes.count)
        peerBuffer.writeBytes(bytes)
        peer.writeAndFlush(peerBuffer, promise: nil)
      }
    default:
      break
    }
  }

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let buffer = unwrapOutboundIn(data)
    let sshData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
    context.write(wrapOutboundOut(sshData), promise: promise)
  }

  func channelInactive(context: ChannelHandlerContext) {
    let peer = self.peer
    peer.eventLoop.execute {
      peer.close(promise: nil)
    }
    context.fireChannelInactive()
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    let peer = self.peer
    peer.eventLoop.execute {
      peer.close(promise: nil)
    }
    context.close(promise: nil)
  }
}
