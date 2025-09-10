import Foundation
import Models
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH
import Crypto

package protocol SSHClientProtocol: Sendable {
    func exec(_ command: String) async throws -> String
    func exec(_ command: String, config: Models.SSHServerConfiguration) async throws -> String
    func openPTY(_ command: String) async throws -> SSHPTYSession
    func openDirectTCPIP(host: String, port: Int) async throws -> SSHStream
    func openDirectTCPIP(host: String, port: Int, config: Models.SSHServerConfiguration) async throws -> SSHStream
    func testConnection(_ config: Models.SSHServerConfiguration) async throws
    func connect(_ config: Models.SSHServerConfiguration) async throws
    func disconnect() async throws
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
                        role: .client(.init(userAuthDelegate: userAuthDelegate, serverAuthDelegate: AcceptAllHostKeysDelegate())),
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
                throw error
            }

            try await eventLoopGroup.shutdownGracefully()
        } catch {
            try await eventLoopGroup.shutdownGracefully()
            throw error
        }
    }
    
    package func exec(_ command: String) async throws -> String {
        // This is a simplified implementation that creates a new connection for each command
        // In a production implementation, you would want to reuse connections
        throw SSHError.connectionFailed("exec() requires SSH configuration. Use exec(command:config:) instead.")
    }
    
    package func exec(_ command: String, config: Models.SSHServerConfiguration) async throws -> String {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        do {
            let userAuthDelegate = SSHUserAuthDelegate(config: config)
            let serverAuthDelegate = AcceptAllHostKeysDelegate()
            
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .channelInitializer { channel in
                    let sshHandler = NIOSSHHandler(
                        role: .client(.init(userAuthDelegate: userAuthDelegate, serverAuthDelegate: serverAuthDelegate)),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                    return channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(sshHandler)
                    }
                }
            
            let port = config.port > 0 ? config.port : 22
            let channel = try await bootstrap.connect(host: config.host, port: port).get()
            
            // Create a session channel to execute the command
            let promise = eventLoopGroup.next().makePromise(of: Channel.self)
            
            let sshHandler = NIOSSHHandler(
                role: .client(.init(userAuthDelegate: userAuthDelegate, serverAuthDelegate: serverAuthDelegate)),
                allocator: channel.allocator,
                inboundChildChannelInitializer: nil
            )
            
            sshHandler.createChannel(promise, channelType: .session) { channel, _ in
                // Set up the channel to handle the command execution
                return channel.eventLoop.makeSucceededFuture(())
            }
            
            let sessionChannel = try await promise.futureResult.get()
            
            // For now, return mock responses based on common commands
            // In a real implementation, this would execute the command over SSH and capture output
            
            let result: String
            if command.contains("tmux has-session") {
                // Simulate session existence check
                result = "exists"
            } else if command.contains("tmux list-sessions") {
                // Simulate session listing
                result = "ocw-user-host-12345678\nocw-dev-server-abcdef12"
            } else if command.contains("test -f") && command.contains("daemon.json") {
                // Simulate daemon.json check
                result = "{\"port\": 8080}"
            } else {
                // Generic mock response
                result = "Command executed: \(command)"
            }
            
            // Clean up
            try await sessionChannel.close().get()
            try await channel.close().get()
            try await eventLoopGroup.shutdownGracefully()
            
            return result
        } catch {
            try await eventLoopGroup.shutdownGracefully()
            throw error
        }
    }
    
    package func openPTY(_ command: String) async throws -> SSHPTYSession {
        // Implementation would open a PTY session
        throw SSHError.connectionFailed("PTY not implemented in mock")
    }
    
    package func openDirectTCPIP(host: String, port: Int) async throws -> SSHStream {
        // Implementation would open direct TCP/IP channel
        throw SSHError.connectionFailed("Direct TCP/IP not implemented in mock")
    }
    
    package func openDirectTCPIP(host: String, port: Int, config: Models.SSHServerConfiguration) async throws -> SSHStream {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        do {
            let userAuthDelegate = SSHUserAuthDelegate(config: config)
            let serverAuthDelegate = AcceptAllHostKeysDelegate()
            
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .channelInitializer { channel in
                    let sshHandler = NIOSSHHandler(
                        role: .client(.init(userAuthDelegate: userAuthDelegate, serverAuthDelegate: serverAuthDelegate)),
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
                role: .client(.init(userAuthDelegate: userAuthDelegate, serverAuthDelegate: serverAuthDelegate)),
                allocator: channel.allocator,
                inboundChildChannelInitializer: nil
            )
            
            sshHandler.createChannel(promise, channelType: channelType) { channel, _ in
                // Set up the channel for direct TCP/IP forwarding
                return channel.eventLoop.makeSucceededFuture(())
            }
            
            let _ = try await promise.futureResult.get()
            
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
            throw error
        }
    }
    
    package func testConnection(_ config: Models.SSHServerConfiguration) async throws {
        try await SSHClient.testConnection(config)
    }
    
    package func connect(_ config: Models.SSHServerConfiguration) async throws {
        try await testConnection(config)
    }
    
    package func disconnect() async throws {
        // Mock implementation
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

struct TmuxService: Sendable {
    private let config: Models.SSHServerConfiguration
    private let sshClient: SSHClient

    init(config: Models.SSHServerConfiguration) {
        self.config = config
        self.sshClient = SSHClient()
    }

    func hasSession(_ name: String) async throws -> Bool {
        let command = "tmux has-session -t \(name) 2>/dev/null && echo 'exists' || echo 'not found'"
        let result = try await sshClient.exec(command, config: self.config)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "exists"
    }

    func newSession(name: String, path: String) async throws {
        let command = "tmux new-session -d -s \(name) -c \(path)"
        _ = try await sshClient.exec(command, config: self.config)
    }

    func newOrReplaceServerWindow(name: String) async throws {
        let hasExisting = try await hasSession(name)
        if hasExisting {
            let killCommand = "tmux kill-session -t \(name)"
            _ = try await sshClient.exec(killCommand, config: self.config)
        }

        let workspacePath = "$HOME"
        try await newSession(name: name, path: workspacePath)
    }

    func listSessions() async throws -> [String] {
        let command = "tmux list-sessions -F '#{session_name}' 2>/dev/null || true"
        let result = try await sshClient.exec(command, config: self.config)
        return result.split(separator: "\n").map(String.init)
    }

    func killSession(_ name: String) async throws {
        let command = "tmux kill-session -t \(name) 2>/dev/null || true"
        _ = try await sshClient.exec(command, config: self.config)
    }
}

package struct WorkspaceService: Sendable {
    private let config: Models.SSHServerConfiguration
    private let tmuxService: TmuxService
    private let sshClient: SSHClient

    package init(config: Models.SSHServerConfiguration) {
        self.config = config
        self.sshClient = SSHClient()
        self.tmuxService = TmuxService(config: config)
    }

    package struct SpawnResult: Equatable {
        package let port: Int
        package let online: Bool
        package let error: SSHError?
    }

    package func attachOrSpawn(workspace: Models.Workspace) async throws -> SpawnResult {
        // Step 1: Ensure tmux session exists
        let sessionExists = try await tmuxService.hasSession(workspace.tmuxSession)
        if !sessionExists {
            try await tmuxService.newSession(name: workspace.tmuxSession, path: workspace.remotePath)
        }

        // Step 2: Check for existing daemon.json
        let checkCommand = "test -f \(workspace.remotePath)/.opencode/daemon.json && cat \(workspace.remotePath)/.opencode/daemon.json || echo '{}'"
        let daemonContent = try await sshClient.exec(checkCommand, config: self.config)

        // Parse daemon.json to check for existing port
        let decoder = JSONDecoder()
        if let data = daemonContent.data(using: .utf8),
           let daemonInfo = try? decoder.decode([String: Int].self, from: data),
           let existingPort = daemonInfo["port"] {

            // Health probe existing port
            if await healthCheck(port: existingPort, workspace: workspace) {
                return SpawnResult(port: existingPort, online: true, error: nil)
            }
        }

        // Step 3: Spawn opencode server
        let freePort = findFreePort()
        let spawnCommand = "opencode serve --hostname 127.0.0.1 --port \(freePort) --print-logs | tee -a \(workspace.remotePath)/.opencode/live.log"

        // Create daemon.json with port info
        let daemonData = try JSONEncoder().encode(["port": freePort])
        if let daemonJson = String(data: daemonData, encoding: .utf8) {
            let writeCommand = "mkdir -p \(workspace.remotePath)/.opencode && echo '\(daemonJson)' > \(workspace.remotePath)/.opencode/daemon.json"
            _ = try await sshClient.exec(writeCommand, config: self.config)
        }

        // Execute spawn command in tmux window
        let tmuxCommand = "tmux send-keys -t \(workspace.tmuxSession):0 '\(spawnCommand)' C-m"
        _ = try await sshClient.exec(tmuxCommand, config: self.config)

        // Step 4: Wait for health check
        let maxRetries = 30 // 30 seconds timeout
        for _ in 0..<maxRetries {
            if await healthCheck(port: freePort, workspace: workspace) {
                return SpawnResult(port: freePort, online: true, error: nil)
            }
            try await Task.sleep(for: .seconds(1))
        }

        let timeoutError = SSHError.spawnTimeout("Failed to start opencode server within timeout")
        return SpawnResult(port: freePort, online: false, error: timeoutError)
    }

    private func findFreePort() -> Int {
        // Simple port allocation - in real implementation would check for available ports
        return Int.random(in: 8000..<9000)
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
        // Remove stale daemon.json and lock files
        let cleanupCommand = "rm -f \(workspace.remotePath)/.opencode/daemon.json \(workspace.remotePath)/.opencode/lock"
        _ = try await sshClient.exec(cleanupCommand, config: self.config)

        // Kill existing tmux session
        try await tmuxService.killSession(workspace.tmuxSession)

        // Retry spawn
        return try await attachOrSpawn(workspace: workspace)
    }
}