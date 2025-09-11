import Foundation

package struct SSHServerConfiguration: Equatable, Hashable, Identifiable {
  package let id: UUID
  package var name: String
  package var host: String
  package var port: Int
  package var username: String
  package var useKeyAuthentication: Bool
  package var privateKeyPath: String
  package var shouldMaintainConnection: Bool

  // Transient properties not stored in JSON
  package var password: String {
    get {
      do {
        return try KeychainManager.loadSSHPassword(for: id.uuidString)
      } catch {
        return ""
      }
    }
    set {
      do {
        if newValue.isEmpty {
          try KeychainManager.deleteSSHPassword(for: id.uuidString)
        } else {
          try KeychainManager.saveSSHPassword(for: id.uuidString, password: newValue)
        }
      } catch {
        print("Failed to save SSH password to keychain: \(error)")
      }
    }
  }

  package var privateKeyData: Data? {
    get {
      do {
        return try KeychainManager.loadSSHPrivateKey(for: id.uuidString)
      } catch {
        return nil
      }
    }
    set {
      do {
        if let data = newValue {
          try KeychainManager.saveSSHPrivateKey(for: id.uuidString, privateKeyData: data)
        } else {
          try KeychainManager.deleteSSHPrivateKey(for: id.uuidString)
        }
      } catch {
        print("Failed to save SSH private key to keychain: \(error)")
      }
    }
  }

  package init(
    id: UUID = UUID(),
    name: String = "",
    host: String = "",
    port: Int = 22,
    username: String = "",
    password: String = "",
    useKeyAuthentication: Bool = false,
    privateKeyPath: String = "",
    privateKeyData: Data? = nil,
    shouldMaintainConnection: Bool = false
  ) {
    self.id = id
    self.name = name
    self.host = host
    self.port = port
    self.username = username
    self.useKeyAuthentication = useKeyAuthentication
    self.privateKeyPath = privateKeyPath
    self.shouldMaintainConnection = shouldMaintainConnection

    // Set password and private key through computed properties (which handle keychain storage)
    self.password = password
    self.privateKeyData = privateKeyData
  }

  package var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && port > 0
      && port <= 65535
      && (useKeyAuthentication
        ? (privateKeyData != nil || !privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        : !password.isEmpty)
  }

  // MARK: - Keychain Management

  package func deleteCredentials() {
    do {
      try KeychainManager.deleteAllSSHCredentials(for: id.uuidString)
    } catch {
      print("Failed to delete SSH credentials from keychain: \(error)")
    }
  }

  // MARK: - Migration Support

  package mutating func migrateFromPlainTextCredentials(plainTextPassword: String?, plainTextKeyData: Data?) {
    if let plainPassword = plainTextPassword, !plainPassword.isEmpty {
      self.password = plainPassword
    }
    if let keyData = plainTextKeyData {
      self.privateKeyData = keyData
    }
  }
}

// MARK: - Codable Implementation (excludes sensitive data)

extension SSHServerConfiguration: Codable {
  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case host
    case port
    case username
    case useKeyAuthentication
    case privateKeyPath
    case shouldMaintainConnection
    // Legacy keys for migration
    case password
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    host = try container.decode(String.self, forKey: .host)
    port = try container.decode(Int.self, forKey: .port)
    username = try container.decode(String.self, forKey: .username)
    useKeyAuthentication = try container.decode(Bool.self, forKey: .useKeyAuthentication)
    privateKeyPath = try container.decode(String.self, forKey: .privateKeyPath)
    shouldMaintainConnection = try container.decode(Bool.self, forKey: .shouldMaintainConnection)

    // Migration: If there's a legacy password in JSON, migrate it to keychain
    if let legacyPassword = try container.decodeIfPresent(String.self, forKey: .password),
       !legacyPassword.isEmpty {
      // Store in keychain via computed property
      self.password = legacyPassword
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(host, forKey: .host)
    try container.encode(port, forKey: .port)
    try container.encode(username, forKey: .username)
    try container.encode(useKeyAuthentication, forKey: .useKeyAuthentication)
    try container.encode(privateKeyPath, forKey: .privateKeyPath)
    try container.encode(shouldMaintainConnection, forKey: .shouldMaintainConnection)

    // Sensitive data (password, privateKeyData) is NOT encoded to JSON
  }
}
