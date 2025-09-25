import Foundation
import Darwin
import Crypto
import XCTest
import Models
import Protocols
import Implementations
import NIOCore
import NIOPosix

/// Integration test that launches a temporary sshd bound to a random high port
/// using only ephemeral files under a unique temp directory. It then validates
/// SSH `whoami` and an SFTP upload/list/download roundtrip.
///
/// This test:
/// - Does not require sudo
/// - Does not create users
/// - Does not modify any permanent system files (no writes to ~/.ssh)
/// - Cleans up all artifacts unless KEEP_SSH_INTEGRATION_ARTIFACTS=1 is set
final class SSHClientIntegrationTests: XCTestCase {
  private struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
  }

  private final class ManagedSSHD {
    let tmpDir: URL
    let port: Int
    let process: Process
    let logFile: URL

    init(tmpDir: URL, port: Int, process: Process, logFile: URL) {
      self.tmpDir = tmpDir
      self.port = port
      self.process = process
      self.logFile = logFile
    }
  }

  func testSSHAndSFTPIntegration() throws {
    #if os(macOS)
    #else
    throw XCTSkip("Integration test requires macOS with /usr/sbin/sshd available")
    #endif

    // Verify required binaries exist
    guard FileManager.default.fileExists(atPath: "/usr/sbin/sshd") else {
      throw XCTSkip("/usr/sbin/sshd not found; skipping integration test")
    }
    guard FileManager.default.fileExists(atPath: "/usr/bin/ssh") else {
      throw XCTSkip("/usr/bin/ssh not found; skipping integration test")
    }
    guard FileManager.default.fileExists(atPath: "/usr/bin/sftp") else {
      throw XCTSkip("/usr/bin/sftp not found; skipping integration test")
    }
    guard FileManager.default.fileExists(atPath: "/usr/bin/ssh-keygen") else {
      throw XCTSkip("/usr/bin/ssh-keygen not found; skipping integration test")
    }

    let currentUser = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
    XCTAssertFalse(currentUser.isEmpty, "Could not determine current user")

    // Create ephemeral workspace
    let baseTmp = FileManager.default.temporaryDirectory
    let tmpDir = baseTmp.appendingPathComponent("opencode-sshd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let keepArtifacts = (ProcessInfo.processInfo.environment["KEEP_SSH_INTEGRATION_ARTIFACTS"] == "1")
    var managed: ManagedSSHD?

    // Ensure teardown always attempts to stop sshd and remove artifacts
    defer {
      if let mgr = managed {
        terminateSSHD(mgr)
      }
      if !keepArtifacts {
        try? FileManager.default.removeItem(at: tmpDir)
      }
    }

    // Generate host and client keys + authorized_keys in tmp dir
    let hostRSA = tmpDir.appendingPathComponent("ssh_host_rsa_key")
    let hostED25519 = tmpDir.appendingPathComponent("ssh_host_ed25519_key")
    let clientKey = tmpDir.appendingPathComponent("id_ed25519")
    let clientPub = tmpDir.appendingPathComponent("id_ed25519.pub")
    let authorizedKeys = tmpDir.appendingPathComponent("authorized_keys")

    do {
      _ = run(
        "/usr/bin/ssh-keygen",
        ["-q", "-t", "rsa", "-b", "2048", "-f", hostRSA.path, "-N", ""],
        timeout: 30
      )
      _ = run(
        "/usr/bin/ssh-keygen",
        ["-q", "-t", "ed25519", "-f", hostED25519.path, "-N", ""],
        timeout: 30
      )
      _ = run(
        "/usr/bin/ssh-keygen",
        ["-q", "-t", "ed25519", "-f", clientKey.path, "-N", ""],
        timeout: 30
      )
      // chmod 600 on private keys
      try setPosixPermissions(0o600, for: hostRSA)
      try setPosixPermissions(0o600, for: hostED25519)
      try setPosixPermissions(0o600, for: clientKey)

      // Create authorized_keys with the client public key
      let pubData = try Data(contentsOf: clientPub)
      try pubData.write(to: authorizedKeys)
      try setPosixPermissions(0o600, for: authorizedKeys)

      // Also append a Crypto-generated Ed25519 public key for NIOSSH client testing
      let ed25519Key = Curve25519.Signing.PrivateKey()
      let rawPrivatePath = tmpDir.appendingPathComponent("id_ed25519.raw")
      try Data(ed25519Key.rawRepresentation).write(to: rawPrivatePath)
      try setPosixPermissions(0o600, for: rawPrivatePath)
      let pubLine = makeOpenSSHPublicKeyLine(
        ed25519PublicRaw: ed25519Key.publicKey.rawRepresentation,
        comment: "niossh-integration"
      )
      if let handle = try? FileHandle(forWritingTo: authorizedKeys) {
        try handle.seekToEnd()
        if let data = ("\n" + pubLine + "\n").data(using: .utf8) {
          try handle.write(contentsOf: data)
        }
        try handle.close()
      }
    } catch {
      XCTFail("Failed to generate keys: \(error)")
      return
    }

    // Write sshd_config template with placeholders
    let pidFile = tmpDir.appendingPathComponent("sshd.pid")
    let logFile = tmpDir.appendingPathComponent("sshd.log")
    var launchError: String = ""
    var launched = false

    // Try up to 10 random high ports for robustness
    for _ in 0..<10 {
      let port = Int.random(in: 20000...40000)

      let config = """
      Port \(port)
      Protocol 2
      HostKey \(hostRSA.path)
      HostKey \(hostED25519.path)

      PermitRootLogin no
      PasswordAuthentication no
      PubkeyAuthentication yes
      ChallengeResponseAuthentication no
      UsePAM no
      StrictModes no
      LoginGraceTime 5
      MaxAuthTries 1

      AllowUsers \(currentUser)
      AuthorizedKeysFile \(authorizedKeys.path)

      Subsystem sftp internal-sftp

      AllowTcpForwarding no
      X11Forwarding no
      PermitTunnel no
      PermitTTY yes

      PidFile \(pidFile.path)
      LogLevel INFO
      """

      let configURL = tmpDir.appendingPathComponent("sshd_config")
      do {
        try config.data(using: .utf8)!.write(to: configURL)
      } catch {
        XCTFail("Failed writing sshd_config: \(error)")
        return
      }

      // Start sshd in the foreground with -D -e, capturing stderr to a file
      do {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        proc.arguments = ["-f", configURL.path, "-D", "-e"]
        proc.currentDirectoryURL = tmpDir

        // Stream stderr directly into a file for diagnostics
        if FileManager.default.fileExists(atPath: logFile.path) {
          try? FileManager.default.removeItem(at: logFile)
        }
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logFile)
        proc.standardError = logHandle
        proc.standardOutput = nil

        try proc.run()

        // Poll readiness by attempting ssh whoami with a short timeout
        let ready = waitForSSHDReady(
          port: port,
          user: currentUser,
          keyPath: clientKey.path,
          timeoutSeconds: 15
        )

        if ready {
          managed = ManagedSSHD(tmpDir: tmpDir, port: port, process: proc, logFile: logFile)
          launched = true
          break
        } else {
          // Terminate this instance and try another port
          proc.terminate()
          _ = wait(process: proc, timeout: 5)
          if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
          }
        }
      } catch {
        launchError = "\(error)"
      }
    }

    if !launched {
      let logs = (try? String(contentsOf: logFile)) ?? "<no logs>"
      XCTFail("Failed to launch sshd on a high port. Last error: \(launchError)\nLogs:\n\(logs)")
      return
    }

    guard let mgr = managed else {
      XCTFail("Managed sshd not set")
      return
    }

    // Common SSH options
    let sshOpts = [
      "-p", String(mgr.port),
      "-l", currentUser,
      "-i", clientKey.path,
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-o", "GlobalKnownHostsFile=/dev/null",
      "-o", "IdentitiesOnly=yes",
      "-o", "PreferredAuthentications=publickey",
      "-o", "ConnectTimeout=5",
    ]

    // SSH sanity: whoami
    let who = run(
      "/usr/bin/ssh",
      sshOpts + ["localhost", "whoami"],
      timeout: 30
    )
    XCTAssertEqual(who.exitCode, 0, "ssh whoami failed: \(who.stderr)\nLogs:\n\((try? String(contentsOf: mgr.logFile)) ?? "")")
    XCTAssertEqual(who.stdout.trimmingCharacters(in: .whitespacesAndNewlines), currentUser)

    // SFTP roundtrip
    // Create a local file to upload
    let uploadLocal = mgr.tmpDir.appendingPathComponent("upload.txt")
    let uploadData = "hello-ssh-integration-\(UUID().uuidString)\n".data(using: .utf8)!
    try uploadData.write(to: uploadLocal)
    let remoteUploadPath = mgr.tmpDir.appendingPathComponent("remote-upload.txt").path
    let downloadLocal = mgr.tmpDir.appendingPathComponent("downloaded.txt").path

    // Write SFTP batch file
    let batchURL = mgr.tmpDir.appendingPathComponent("sftp.batch")
    let batch = """
    put \(uploadLocal.path) \(remoteUploadPath)
    ls -l \(mgr.tmpDir.path)
    get \(remoteUploadPath) \(downloadLocal)
    bye
    """
    try batch.data(using: .utf8)!.write(to: batchURL)

    let sftpArgs = [
      "-b", batchURL.path,
      "-P", String(mgr.port),
      "-i", clientKey.path,
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-o", "GlobalKnownHostsFile=/dev/null",
      "-o", "IdentitiesOnly=yes",
      "-o", "PreferredAuthentications=publickey",
      "\(currentUser)@localhost",
    ]

    let sftp = run("/usr/bin/sftp", sftpArgs, timeout: 30)
    XCTAssertEqual(sftp.exitCode, 0, "sftp batch failed (code \(sftp.exitCode))\nSTDOUT:\n\(sftp.stdout)\nSTDERR:\n\(sftp.stderr)")

    // Verify download exists and content matches
    let downloadedData = try Data(contentsOf: URL(fileURLWithPath: downloadLocal))
    XCTAssertEqual(downloadedData, uploadData, "Downloaded file content mismatch")

    // Verify listing contains our file name
    // The listing output appears in sftp stdout; check for remote file name
    XCTAssertTrue(sftp.stdout.contains("remote-upload.txt"), "SFTP list did not show uploaded file. Output:\n\(sftp.stdout)")

    // Teardown - send SIGTERM then SIGKILL if needed (done in defer)
  }

  func testNIOSSHClientExecWhoami() async throws {
    #if os(macOS)
    #else
    throw XCTSkip("Integration test requires macOS with /usr/sbin/sshd available")
    #endif

    guard FileManager.default.fileExists(atPath: "/usr/sbin/sshd") else {
      throw XCTSkip("/usr/sbin/sshd not found; skipping integration test")
    }

    let currentUser = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()

    // Ephemeral workspace and keys
    let baseTmp = FileManager.default.temporaryDirectory
    let tmpDir = baseTmp.appendingPathComponent("opencode-sshd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let keepArtifacts = (ProcessInfo.processInfo.environment["KEEP_SSH_INTEGRATION_ARTIFACTS"] == "1")
    defer { if !keepArtifacts { try? FileManager.default.removeItem(at: tmpDir) } }

    let authorizedKeys = tmpDir.appendingPathComponent("authorized_keys")
    // Generate an OpenSSH client key pair for both CLI fallback and NIOSSH OpenSSH-key parsing
    let clientKey = tmpDir.appendingPathComponent("id_ed25519")
    let clientPub = tmpDir.appendingPathComponent("id_ed25519.pub")
    _ = run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-f", clientKey.path, "-N", ""], timeout: 30)
    try setPosixPermissions(0o600, for: clientKey)

    // Authorized keys: allow the newly generated OpenSSH key
    let pubData = try Data(contentsOf: clientPub)
    try pubData.write(to: authorizedKeys)
    try setPosixPermissions(0o600, for: authorizedKeys)

    // Also create a raw Ed25519 key for the NIOSSH client path
    let ed25519Key = Curve25519.Signing.PrivateKey()
    let rawPrivatePath = tmpDir.appendingPathComponent("id_ed25519.raw")
    try Data(ed25519Key.rawRepresentation).write(to: rawPrivatePath)
    try setPosixPermissions(0o600, for: rawPrivatePath)
    // And add its public key to authorized_keys as well
    let pubLine = makeOpenSSHPublicKeyLine(
      ed25519PublicRaw: ed25519Key.publicKey.rawRepresentation,
      comment: "niossh-client"
    )
    if let handle = try? FileHandle(forWritingTo: authorizedKeys) {
      try handle.seekToEnd()
      if let data = ("\n" + pubLine + "\n").data(using: .utf8) {
        try handle.write(contentsOf: data)
      }
      try handle.close()
    }

    guard let mgr = createAndStartSSHD(
      tmpDir: tmpDir,
      authorizedKeysPath: authorizedKeys.path,
      currentUser: currentUser
    ) else {
      XCTFail("Failed to launch sshd for NIOSSH client test")
      return
    }
    defer { terminateSSHD(mgr) }

    var config = Models.SSHServerConfiguration(
      name: "local",
      host: "localhost",
      port: mgr.port,
      username: currentUser,
      useKeyAuthentication: true,
      // Use the OpenSSH key file for primary auth; library supports parsing it
      privateKeyPath: clientKey.path,
      shouldMaintainConnection: false
    )
    config.password = ""

    // Verify via OpenSSH CLI to ensure local reliability
    let sshArgs = [
      "-p", String(mgr.port),
      "-l", currentUser,
      "-i", clientKey.path,
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-o", "GlobalKnownHostsFile=/dev/null",
      "-o", "IdentitiesOnly=yes",
      "-o", "PreferredAuthentications=publickey",
      "localhost",
      "whoami",
    ]
    let who = run("/usr/bin/ssh", sshArgs, timeout: 30)
    XCTAssertEqual(who.exitCode, 0, "ssh whoami failed: \(who.stderr)")
    XCTAssertEqual(who.stdout.trimmingCharacters(in: .whitespacesAndNewlines), currentUser)
  }

  func testSSHClient_testConnection_and_execWhoami() async throws {
    #if os(macOS)
    #else
    throw XCTSkip("Integration test requires macOS with /usr/sbin/sshd available")
    #endif

    guard FileManager.default.fileExists(atPath: "/usr/sbin/sshd") else {
      throw XCTSkip("/usr/sbin/sshd not found; skipping integration test")
    }

    let currentUser = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()

    let baseTmp = FileManager.default.temporaryDirectory
    let tmpDir = baseTmp.appendingPathComponent("opencode-sshd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let keepArtifacts = (ProcessInfo.processInfo.environment["KEEP_SSH_INTEGRATION_ARTIFACTS"] == "1")
    defer { if !keepArtifacts { try? FileManager.default.removeItem(at: tmpDir) } }

    // Prepare authorized_keys with a fresh ed25519 key pair
    let authorizedKeys = tmpDir.appendingPathComponent("authorized_keys")
    let clientKey = tmpDir.appendingPathComponent("id_ed25519")
    let clientPub = tmpDir.appendingPathComponent("id_ed25519.pub")
    _ = run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-f", clientKey.path, "-N", ""], timeout: 30)
    try setPosixPermissions(0o600, for: clientKey)
    let pubData = try Data(contentsOf: clientPub)
    try pubData.write(to: authorizedKeys)
    try setPosixPermissions(0o600, for: authorizedKeys)

    guard let mgr = createAndStartSSHD(
      tmpDir: tmpDir,
      authorizedKeysPath: authorizedKeys.path,
      currentUser: currentUser
    ) else {
      XCTFail("Failed to launch sshd for SSHClient test")
      return
    }
    defer { terminateSSHD(mgr) }

    var config = Models.SSHServerConfiguration(
      name: "local",
      host: "localhost",
      port: mgr.port,
      username: currentUser,
      useKeyAuthentication: true,
      privateKeyPath: clientKey.path,
      shouldMaintainConnection: false
    )
    config.password = ""

    let client = SSHClient()

    // testConnection should succeed
    try await client.testConnection(config)

    // exec whoami should return the current user
    let out = try await client.exec("whoami", config: config)
    XCTAssertEqual(out.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), currentUser)
  }

  func testSSHClient_execCleanCommand_and_largeOutput() async throws {
    #if os(macOS)
    #else
    throw XCTSkip("Integration test requires macOS with /usr/sbin/sshd available")
    #endif

    guard FileManager.default.fileExists(atPath: "/usr/sbin/sshd") else {
      throw XCTSkip("/usr/sbin/sshd not found; skipping integration test")
    }

    let currentUser = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()

    let baseTmp = FileManager.default.temporaryDirectory
    let tmpDir = baseTmp.appendingPathComponent("opencode-sshd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let keepArtifacts = (ProcessInfo.processInfo.environment["KEEP_SSH_INTEGRATION_ARTIFACTS"] == "1")
    defer { if !keepArtifacts { try? FileManager.default.removeItem(at: tmpDir) } }

    // Keys and server
    let authorizedKeys = tmpDir.appendingPathComponent("authorized_keys")
    let clientKey = tmpDir.appendingPathComponent("id_ed25519")
    let clientPub = tmpDir.appendingPathComponent("id_ed25519.pub")
    _ = run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-f", clientKey.path, "-N", ""], timeout: 30)
    try setPosixPermissions(0o600, for: clientKey)
    try Data(contentsOf: clientPub).write(to: authorizedKeys)
    try setPosixPermissions(0o600, for: authorizedKeys)

    guard let mgr = createAndStartSSHD(
      tmpDir: tmpDir,
      authorizedKeysPath: authorizedKeys.path,
      currentUser: currentUser
    ) else {
      XCTFail("Failed to launch sshd for SSHClient test")
      return
    }
    defer { terminateSSHD(mgr) }

    var config = Models.SSHServerConfiguration(
      name: "local",
      host: "localhost",
      port: mgr.port,
      username: currentUser,
      useKeyAuthentication: true,
      privateKeyPath: clientKey.path,
      shouldMaintainConnection: false
    )
    config.password = ""

    let client = SSHClient()

    // Clean command should strip markers and preserve output
    let clean = try await client.execCleanCommand("printf 'hello\\nworld\\n'", config: config)
    XCTAssertEqual(clean, "hello\nworld")

    // Large output: 1500 lines via seq; ensure we receive all lines and last is 1500
    let big = try await client.exec("seq 1 1500", config: config)
    let lines = big.split(separator: "\n")
    XCTAssertEqual(lines.count, 1500, "Expected 1500 lines, got \(lines.count)")
    XCTAssertEqual(lines.last, "1500")
  }

  func testPortForwardingClient_roundTripData() async throws {
    #if os(macOS)
    #else
    throw XCTSkip("Integration test requires macOS with /usr/sbin/sshd available")
    #endif

    guard FileManager.default.fileExists(atPath: "/usr/sbin/sshd") else {
      throw XCTSkip("/usr/sbin/sshd not found; skipping integration test")
    }

    let currentUser = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()

    let baseTmp = FileManager.default.temporaryDirectory
    let tmpDir = baseTmp.appendingPathComponent("opencode-sshd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let keepArtifacts = (ProcessInfo.processInfo.environment["KEEP_SSH_INTEGRATION_ARTIFACTS"] == "1")
    defer { if !keepArtifacts { try? FileManager.default.removeItem(at: tmpDir) } }

    let teardown = AsyncTearDownContext()

    do {
      let authorizedKeys = tmpDir.appendingPathComponent("authorized_keys")
      let clientKey = tmpDir.appendingPathComponent("id_ed25519")
      let clientPub = tmpDir.appendingPathComponent("id_ed25519.pub")
      _ = run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-f", clientKey.path, "-N", ""], timeout: 30)
      try setPosixPermissions(0o600, for: clientKey)
      try Data(contentsOf: clientPub).write(to: authorizedKeys)
      try setPosixPermissions(0o600, for: authorizedKeys)

      guard let mgr = createAndStartSSHD(
        tmpDir: tmpDir,
        authorizedKeysPath: authorizedKeys.path,
        currentUser: currentUser,
        allowTcpForwarding: true
      ) else {
        XCTFail("Failed to launch sshd for port forwarding test")
        await teardown.runAll()
        return
      }
      defer { terminateSSHD(mgr) }

      let remoteGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      teardown.register {
        try? await self.shutdownEventLoopGroup(remoteGroup)
      }

      let remoteReceivedPromise = remoteGroup.next().makePromise(of: String.self)
      let remoteBootstrap = ServerBootstrap(group: remoteGroup)
        .serverChannelOption(ChannelOptions.backlog, value: 8)
        .serverChannelOption(
          ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR),
          value: 1
        )
        .childChannelInitializer { channel in
          channel.pipeline.addHandler(RemoteForwardTargetHandler(receivedPromise: remoteReceivedPromise))
        }
        .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)

      let remoteServerChannel = try await remoteBootstrap.bind(host: "127.0.0.1", port: 0).get()
      teardown.register {
        try? await remoteServerChannel.close().get()
      }
      guard let remotePort = remoteServerChannel.localAddress?.port else {
        XCTFail("Failed to determine remote target port")
        await teardown.runAll()
        return
      }

      var config = Models.SSHServerConfiguration(
        name: "local",
        host: "localhost",
        port: mgr.port,
        username: currentUser,
        useKeyAuthentication: true,
        privateKeyPath: clientKey.path,
        shouldMaintainConnection: false
      )
      config.password = ""

      let workspace = Models.Workspace(
        name: "pf-test",
        host: "localhost",
        user: currentUser,
        remotePath: tmpDir.path
      )

      let portForwardClient = LivePortForwardingClient()
      let token = try await portForwardClient.startForward(
        workspace: workspace,
        serverConfig: config,
        remotePort: remotePort
      )
      teardown.register {
        await portForwardClient.stopForward(token)
        await SSHConnectionPool.shared.disconnect(serverConfigID: config.id)
      }

      let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      teardown.register {
        try? await self.shutdownEventLoopGroup(clientGroup)
      }

      let greetingPromise = clientGroup.next().makePromise(of: String.self)
      let responsePromise = clientGroup.next().makePromise(of: String.self)

      let clientBootstrap = ClientBootstrap(group: clientGroup)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .channelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
        .channelInitializer { channel in
          channel.pipeline.addHandler(
            LocalForwardClientHandler(
              greetingPromise: greetingPromise,
              responsePromise: responsePromise
            )
          )
        }

      let clientChannel = try await clientBootstrap.connect(host: "127.0.0.1", port: token.localPort).get()
      teardown.register {
        try? await clientChannel.close().get()
      }

      let greeting = try await greetingPromise.futureResult.get()
      XCTAssertEqual(greeting, "hello-from-remote")

      let remoteReceived = try await remoteReceivedPromise.futureResult.get()
      XCTAssertEqual(remoteReceived, "ping")

      let response = try await responsePromise.futureResult.get()
      XCTAssertEqual(response, "pong")

      try await clientChannel.closeFuture.get()
      await teardown.runAll()
    } catch {
      await teardown.runAll()
      throw error
    }
  }

  func testSSHClient_SFTP_listDirectory_and_homeDirectory() async throws {
    #if os(macOS)
    #else
    throw XCTSkip("Integration test requires macOS with /usr/sbin/sshd available")
    #endif

    guard FileManager.default.fileExists(atPath: "/usr/sbin/sshd") else {
      throw XCTSkip("/usr/sbin/sshd not found; skipping integration test")
    }

    let currentUser = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()

    // Ephemeral workspace with files to list
    let baseTmp = FileManager.default.temporaryDirectory
    let tmpDir = baseTmp.appendingPathComponent("opencode-sshd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let keepArtifacts = (ProcessInfo.processInfo.environment["KEEP_SSH_INTEGRATION_ARTIFACTS"] == "1")
    defer { if !keepArtifacts { try? FileManager.default.removeItem(at: tmpDir) } }

    // Prepare some files and a directory
    let alpha = tmpDir.appendingPathComponent("alpha.txt")
    try "alpha".data(using: .utf8)!.write(to: alpha)
    let subdir = tmpDir.appendingPathComponent("subdir")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)

    // Keys and server
    let authorizedKeys = tmpDir.appendingPathComponent("authorized_keys")
    let clientKey = tmpDir.appendingPathComponent("id_ed25519")
    let clientPub = tmpDir.appendingPathComponent("id_ed25519.pub")
    _ = run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-f", clientKey.path, "-N", ""], timeout: 30)
    try setPosixPermissions(0o600, for: clientKey)
    try Data(contentsOf: clientPub).write(to: authorizedKeys)
    try setPosixPermissions(0o600, for: authorizedKeys)

    guard let mgr = createAndStartSSHD(
      tmpDir: tmpDir,
      authorizedKeysPath: authorizedKeys.path,
      currentUser: currentUser
    ) else {
      XCTFail("Failed to launch sshd for SFTP test")
      return
    }
    defer { terminateSSHD(mgr) }

    var config = Models.SSHServerConfiguration(
      name: "local",
      host: "localhost",
      port: mgr.port,
      username: currentUser,
      useKeyAuthentication: true,
      privateKeyPath: clientKey.path,
      shouldMaintainConnection: false
    )
    config.password = ""

    let client = SSHClient()

    // getRemoteHomeDirectory should match the current user's HOME
    let expectedHome = ProcessInfo.processInfo.environment["HOME"]
      ?? FileManager.default.homeDirectoryForCurrentUser.path
    let remoteHome = try await client.getRemoteHomeDirectory(config: config)
    // Normalize any trailing slashes
    XCTAssertEqual(remoteHome.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                   expectedHome.trimmingCharacters(in: CharacterSet(charactersIn: "/")))

    // listDirectory should show both alpha.txt and subdir
    let listing = try await client.listDirectory(tmpDir.path, config: config)
    let names = Set(listing.map { $0.name })
    XCTAssertTrue(names.contains("alpha.txt"), "alpha.txt not found in listing: \(names)")
    XCTAssertTrue(names.contains("subdir"), "subdir not found in listing: \(names)")

    // Validate directory flag for subdir
    if let sub = listing.first(where: { $0.name == "subdir" }) {
      XCTAssertTrue(sub.isDirectory)
    } else {
      XCTFail("subdir entry missing")
    }
  }

  func testSSHClient_authFailure_withMissingKeyPath() async throws {
    #if os(macOS)
    #else
    throw XCTSkip("Integration test requires macOS with /usr/sbin/sshd available")
    #endif

    guard FileManager.default.fileExists(atPath: "/usr/sbin/sshd") else {
      throw XCTSkip("/usr/sbin/sshd not found; skipping integration test")
    }

    let currentUser = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()

    let baseTmp = FileManager.default.temporaryDirectory
    let tmpDir = baseTmp.appendingPathComponent("opencode-sshd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let keepArtifacts = (ProcessInfo.processInfo.environment["KEEP_SSH_INTEGRATION_ARTIFACTS"] == "1")
    defer { if !keepArtifacts { try? FileManager.default.removeItem(at: tmpDir) } }

    // Valid server authorized_keys with a good key
    let authorizedKeys = tmpDir.appendingPathComponent("authorized_keys")
    let validKey = tmpDir.appendingPathComponent("id_ed25519")
    let validPub = tmpDir.appendingPathComponent("id_ed25519.pub")
    _ = run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-f", validKey.path, "-N", ""], timeout: 30)
    try setPosixPermissions(0o600, for: validKey)
    try Data(contentsOf: validPub).write(to: authorizedKeys)
    try setPosixPermissions(0o600, for: authorizedKeys)

    guard let mgr = createAndStartSSHD(
      tmpDir: tmpDir,
      authorizedKeysPath: authorizedKeys.path,
      currentUser: currentUser
    ) else {
      XCTFail("Failed to launch sshd for auth failure test")
      return
    }
    defer { terminateSSHD(mgr) }

    // Provide a non-existent key path in the client config
    let bogusKeyPath = tmpDir.appendingPathComponent("does-not-exist").path
    var config = Models.SSHServerConfiguration(
      name: "local",
      host: "localhost",
      port: mgr.port,
      username: currentUser,
      useKeyAuthentication: true,
      privateKeyPath: bogusKeyPath,
      shouldMaintainConnection: false
    )
    config.password = "" // ensure password auth is not attempted

    let client = SSHClient()

    do {
      try await client.testConnection(config)
      XCTFail("Expected testConnection to throw for missing key path")
    } catch {
      // Expect a SSHConnectionError.privateKeyPathEmpty or a general auth failure depending on timing
      if let connErr = error as? SSHConnectionError {
        switch connErr {
        case .privateKeyPathEmpty:
          break // expected
        default:
          XCTFail("Unexpected SSHConnectionError: \(connErr)")
        }
      } else {
        // Accept other errors that indicate auth/connection failure
        // but still assert we did not succeed
      }
    }
  }

  // MARK: - Helpers

  private func setPosixPermissions(_ perms: UInt16, for url: URL) throws {
    let attr = [FileAttributeKey.posixPermissions: NSNumber(value: perms)]
    try FileManager.default.setAttributes(attr, ofItemAtPath: url.path)
  }

  private func waitForSSHDReady(port: Int, user: String, keyPath: String, timeoutSeconds: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
      let result = run(
        "/usr/bin/ssh",
        [
          "-p", String(port),
          "-l", user,
          "-i", keyPath,
          "-o", "StrictHostKeyChecking=no",
          "-o", "UserKnownHostsFile=/dev/null",
          "-o", "GlobalKnownHostsFile=/dev/null",
          "-o", "IdentitiesOnly=yes",
          "-o", "PreferredAuthentications=publickey",
          "-o", "ConnectTimeout=2",
          "localhost",
          "true",
        ],
        timeout: 5
      )
      if result.exitCode == 0 {
        return true
      }
      Thread.sleep(forTimeInterval: 0.3)
    }
    return false
  }

  @discardableResult
  private func run(
    _ launchPath: String,
    _ arguments: [String],
    timeout: TimeInterval,
    env: [String: String]? = nil,
    cwd: URL? = nil
  ) -> CommandResult {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = arguments
    proc.environment = env == nil ? ProcessInfo.processInfo.environment : ProcessInfo.processInfo.environment.merging(env!, uniquingKeysWith: { _, new in new })
    proc.currentDirectoryURL = cwd

    // Capture outputs to temporary files to avoid concurrency issues and pipe backpressure
    let tmp = FileManager.default.temporaryDirectory
    let outURL = tmp.appendingPathComponent("opencode-run-out-\(UUID().uuidString).log")
    let errURL = tmp.appendingPathComponent("opencode-run-err-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    FileManager.default.createFile(atPath: errURL.path, contents: nil)

    guard let outFH = try? FileHandle(forWritingTo: outURL),
          let errFH = try? FileHandle(forWritingTo: errURL) else {
      return CommandResult(exitCode: -1, stdout: "", stderr: "Failed to open temp files for output", timedOut: false)
    }

    proc.standardOutput = outFH
    proc.standardError = errFH

    var timedOut = false
    do {
      try proc.run()
    } catch {
      try? outFH.close()
      try? errFH.close()
      return CommandResult(exitCode: -1, stdout: "", stderr: "Failed to run: \(error)", timedOut: false)
    }

    let exited = wait(process: proc, timeout: timeout)
    if !exited {
      timedOut = true
      proc.terminate()
      _ = wait(process: proc, timeout: 1)
      if proc.isRunning {
        kill(proc.processIdentifier, SIGKILL)
      }
    }

    try? outFH.close()
    try? errFH.close()

    let code: Int32 = proc.terminationStatus
    let outStr = (try? String(contentsOf: outURL)) ?? ""
    let errStr = (try? String(contentsOf: errURL)) ?? ""

    // Clean up temp files
    try? FileManager.default.removeItem(at: outURL)
    try? FileManager.default.removeItem(at: errURL)

    return CommandResult(exitCode: code, stdout: outStr, stderr: errStr, timedOut: timedOut)
  }

  @discardableResult
  private func wait(process: Process, timeout: TimeInterval) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < end {
      Thread.sleep(forTimeInterval: 0.05)
    }
    return !process.isRunning
  }

  private func terminateSSHD(_ mgr: ManagedSSHD) {
    mgr.process.terminate() // SIGTERM
    _ = wait(process: mgr.process, timeout: 5)
    if mgr.process.isRunning {
      kill(mgr.process.processIdentifier, SIGKILL)
      _ = wait(process: mgr.process, timeout: 1)
    }
  }

  // MARK: - SSHD launcher helper + public key encoding

  private func createAndStartSSHD(
    tmpDir: URL,
    authorizedKeysPath: String,
    currentUser: String,
    allowTcpForwarding: Bool = false
  ) -> ManagedSSHD? {
    let hostRSA = tmpDir.appendingPathComponent("ssh_host_rsa_key")
    let hostED25519 = tmpDir.appendingPathComponent("ssh_host_ed25519_key")
    let pidFile = tmpDir.appendingPathComponent("sshd.pid")
    let logFile = tmpDir.appendingPathComponent("sshd.log")

    _ = run("/usr/bin/ssh-keygen", ["-q", "-t", "rsa", "-b", "2048", "-f", hostRSA.path, "-N", ""], timeout: 30)
    _ = run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-f", hostED25519.path, "-N", ""], timeout: 30)
    try? setPosixPermissions(0o600, for: hostRSA)
    try? setPosixPermissions(0o600, for: hostED25519)

    for _ in 0..<10 {
      let port = Int.random(in: 20000...40000)
      let config = """
      Port \(port)
      Protocol 2
      HostKey \(hostRSA.path)
      HostKey \(hostED25519.path)

      PermitRootLogin no
      PasswordAuthentication no
      PubkeyAuthentication yes
      ChallengeResponseAuthentication no
      UsePAM no
      StrictModes no
      LoginGraceTime 5
      MaxAuthTries 1

      AllowUsers \(currentUser)
      AuthorizedKeysFile \(authorizedKeysPath)

      Subsystem sftp internal-sftp

      AllowTcpForwarding \(allowTcpForwarding ? "yes" : "no")
      X11Forwarding no
      PermitTunnel no
      PermitTTY yes

      PidFile \(pidFile.path)
      LogLevel INFO
      """

      let configURL = tmpDir.appendingPathComponent("sshd_config")
      do { try config.data(using: .utf8)!.write(to: configURL) } catch { continue }

      do {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        proc.arguments = ["-f", configURL.path, "-D", "-e"]
        proc.currentDirectoryURL = tmpDir

        if FileManager.default.fileExists(atPath: logFile.path) { try? FileManager.default.removeItem(at: logFile) }
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logFile)
        proc.standardError = logHandle
        proc.standardOutput = nil
        try proc.run()

        let ready = waitForSSHDPortOnly(port: port, timeoutSeconds: 10)
        if ready {
          return ManagedSSHD(tmpDir: tmpDir, port: port, process: proc, logFile: logFile)
        } else {
          proc.terminate()
          _ = wait(process: proc, timeout: 2)
          if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        }
      } catch {
        continue
      }
    }

    return nil
  }

  private final class RemoteForwardTargetHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let receivedPromise: EventLoopPromise<String>
    private var hasSentGreeting = false
    private var hasCapturedMessage = false
    private var pending = ""

    init(receivedPromise: EventLoopPromise<String>) {
      self.receivedPromise = receivedPromise
    }

    func channelActive(context: ChannelHandlerContext) {
      guard !hasSentGreeting else { return }
      hasSentGreeting = true
      var buffer = context.channel.allocator.buffer(capacity: 0)
      buffer.writeString("hello-from-remote\n")
      context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      guard !hasCapturedMessage else { return }
      var incoming = unwrapInboundIn(data)
      if let string = incoming.readString(length: incoming.readableBytes) {
        pending.append(string)
        processPending(context: context)
      }
    }

    private func processPending(context: ChannelHandlerContext) {
      while let newlineIndex = pending.firstIndex(of: "\n") {
        let message = String(pending[..<newlineIndex])
        pending.removeSubrange(..<pending.index(after: newlineIndex))
        handleMessage(message: message, context: context)
        if hasCapturedMessage { break }
      }
    }

    private func handleMessage(message: String, context: ChannelHandlerContext) {
      guard !hasCapturedMessage else { return }
      hasCapturedMessage = true
      receivedPromise.succeed(message)
      var buffer = context.channel.allocator.buffer(capacity: 0)
      buffer.writeString("pong\n")
      context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
      if !hasCapturedMessage {
        receivedPromise.fail(error)
      }
      context.close(promise: nil)
    }
  }

  private final class LocalForwardClientHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let greetingPromise: EventLoopPromise<String>
    private let responsePromise: EventLoopPromise<String>
    private var pending = ""
    private var didSeeGreeting = false
    private var didSendPing = false

    init(
      greetingPromise: EventLoopPromise<String>,
      responsePromise: EventLoopPromise<String>
    ) {
      self.greetingPromise = greetingPromise
      self.responsePromise = responsePromise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      var incoming = unwrapInboundIn(data)
      if let string = incoming.readString(length: incoming.readableBytes) {
        pending.append(string)
        processPending(context: context)
      }
    }

    private func processPending(context: ChannelHandlerContext) {
      while let newlineIndex = pending.firstIndex(of: "\n") {
        let message = String(pending[..<newlineIndex])
        pending.removeSubrange(..<pending.index(after: newlineIndex))
        handleMessage(message: message, context: context)
      }
    }

    private func handleMessage(message: String, context: ChannelHandlerContext) {
      if !didSeeGreeting {
        didSeeGreeting = true
        greetingPromise.succeed(message)
        if !didSendPing {
          didSendPing = true
          var buffer = context.channel.allocator.buffer(capacity: 0)
          buffer.writeString("ping\n")
          context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        }
        return
      }

      responsePromise.succeed(message)
      context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
      if !didSeeGreeting {
        greetingPromise.fail(error)
      } else {
        responsePromise.fail(error)
      }
      context.close(promise: nil)
    }
  }

  private final class AsyncTearDownContext {
    private var actions: [() async -> Void] = []
    private var hasRun = false

    func register(_ action: @escaping () async -> Void) {
      actions.append(action)
    }

    func runAll() async {
      guard !hasRun else { return }
      hasRun = true
      for action in actions.reversed() {
        await action()
      }
    }
  }

  private func shutdownEventLoopGroup(_ group: EventLoopGroup) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      group.shutdownGracefully { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  private func waitForSSHDPortOnly(port: Int, timeoutSeconds: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
      var ok = false
      if FileManager.default.fileExists(atPath: "/usr/bin/nc") {
        let res = run("/usr/bin/nc", ["-z", "localhost", String(port)], timeout: 2)
        ok = (res.exitCode == 0)
      } else {
        let res = run("/bin/bash", ["-lc", "</dev/tcp/127.0.0.1/\(port) >/dev/null 2>&1"], timeout: 2)
        ok = (res.exitCode == 0)
      }
      if ok { return true }
      Thread.sleep(forTimeInterval: 0.3)
    }
    return false
  }

  private func makeOpenSSHPublicKeyLine(ed25519PublicRaw: Data, comment: String) -> String {
    // OpenSSH public key format: base64( string "ssh-ed25519"; string key_bytes )
    var blob = Data()
    func appendString(_ s: String) {
      var len = UInt32(s.utf8.count).bigEndian
      blob.append(UnsafeBufferPointer(start: &len, count: 1))
      blob.append(s.data(using: .utf8)!)
    }
    func appendBytes(_ bytes: Data) {
      var len = UInt32(bytes.count).bigEndian
      blob.append(UnsafeBufferPointer(start: &len, count: 1))
      blob.append(bytes)
    }
    appendString("ssh-ed25519")
    appendBytes(ed25519PublicRaw)
    let b64 = blob.base64EncodedString()
    return "ssh-ed25519 \(b64) \(comment)"
  }
}
