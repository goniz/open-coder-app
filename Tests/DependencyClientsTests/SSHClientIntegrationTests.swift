import Foundation
import Darwin
import Crypto
import XCTest
import Models
import DependencyClients

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
    let ed25519Key = Curve25519.Signing.PrivateKey()
    let rawPrivatePath = tmpDir.appendingPathComponent("id_ed25519.raw")
    try Data(ed25519Key.rawRepresentation).write(to: rawPrivatePath)
    try setPosixPermissions(0o600, for: rawPrivatePath)
    let pubLine = makeOpenSSHPublicKeyLine(
      ed25519PublicRaw: ed25519Key.publicKey.rawRepresentation,
      comment: "niossh-client"
    )
    try (pubLine + "\n").data(using: .utf8)!.write(to: authorizedKeys)
    try setPosixPermissions(0o600, for: authorizedKeys)

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
      privateKeyPath: rawPrivatePath.path,
      shouldMaintainConnection: false
    )
    config.password = ""

    let client = SSHClient()
    let output = try await client.execCleanCommand("whoami", config: config)
    XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), currentUser)
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

  private func createAndStartSSHD(tmpDir: URL, authorizedKeysPath: String, currentUser: String) -> ManagedSSHD? {
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

      AllowUsers \(currentUser)
      AuthorizedKeysFile \(authorizedKeysPath)

      Subsystem sftp internal-sftp

      AllowTcpForwarding no
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
