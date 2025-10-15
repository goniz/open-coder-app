import Foundation
import Security

public struct KeychainManager: Sendable {

  private static let service = "com.opencoder.ssh-credentials"

  public enum KeychainError: Error, LocalizedError, Sendable {

    case itemNotFound
    case duplicateItem
    case invalidData
    case unexpectedPasswordData
    case unhandledError(status: OSStatus)

    public var errorDescription: String? {
      switch self {
      case .itemNotFound:
        return "The item was not found in the keychain."
      case .duplicateItem:
        return "The item already exists in the keychain."
      case .invalidData:
        return "Invalid data provided to keychain."
      case .unexpectedPasswordData:
        return "Unexpected password data found in keychain."
      case .unhandledError(let status):
        return "Keychain error with status: \(status)"
      }
    }
  }

  // MARK: - SSH Password Management

#if targetEnvironment(simulator)

  public static func saveSSHPassword(for serverID: String, password: String) throws {
    UserDefaults.standard.set(password, forKey: "ssh-password-\(serverID)")
  }

  public static func loadSSHPassword(for serverID: String) throws -> String {
    guard let password = UserDefaults.standard.string(forKey: "ssh-password-\(serverID)") else {
      throw KeychainError.itemNotFound
    }
    return password
  }

  public static func deleteSSHPassword(for serverID: String) throws {
    UserDefaults.standard.removeObject(forKey: "ssh-password-\(serverID)")
  }

  public static func saveSSHPrivateKey(for serverID: String, privateKeyData: Data) throws {
    UserDefaults.standard.set(privateKeyData, forKey: "ssh-privatekey-\(serverID)")
  }

  public static func loadSSHPrivateKey(for serverID: String) throws -> Data {
    guard let data = UserDefaults.standard.data(forKey: "ssh-privatekey-\(serverID)") else {
      throw KeychainError.itemNotFound
    }
    return data
  }

  public static func deleteSSHPrivateKey(for serverID: String) throws {
    UserDefaults.standard.removeObject(forKey: "ssh-privatekey-\(serverID)")
  }

#else

  // MARK: - SSH Password Management

  public static func saveSSHPassword(for serverID: String, password: String) throws {
    let passwordData = password.data(using: .utf8) ?? Data()

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "ssh-password-\(serverID)",
      kSecValueData as String: passwordData
    ]

    let status = SecItemAdd(query as CFDictionary, nil)

    switch status {
    case errSecSuccess:
      break
    case errSecDuplicateItem:
      // Update existing item
      try updateSSHPassword(for: serverID, password: password)
    default:
      throw KeychainError.unhandledError(status: status)
    }
  }

  public static func loadSSHPassword(for serverID: String) throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "ssh-password-\(serverID)",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    switch status {
    case errSecSuccess:
      guard let passwordData = result as? Data,
        let password = String(data: passwordData, encoding: .utf8)
      else {
        throw KeychainError.unexpectedPasswordData
      }
      return password
    case errSecItemNotFound:
      throw KeychainError.itemNotFound
    default:
      throw KeychainError.unhandledError(status: status)
    }
  }

  private static func updateSSHPassword(for serverID: String, password: String) throws {
    let passwordData = password.data(using: .utf8) ?? Data()

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "ssh-password-\(serverID)"
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: passwordData
    ]

    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    guard status == errSecSuccess else {
      throw KeychainError.unhandledError(status: status)
    }
  }

  public static func deleteSSHPassword(for serverID: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "ssh-password-\(serverID)"
    ]

    let status = SecItemDelete(query as CFDictionary)

    switch status {
    case errSecSuccess, errSecItemNotFound:
      break  // Success or item didn't exist
    default:
      throw KeychainError.unhandledError(status: status)
    }
  }

  // MARK: - SSH Private Key Management

  public static func saveSSHPrivateKey(for serverID: String, privateKeyData: Data) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "ssh-privatekey-\(serverID)",
      kSecValueData as String: privateKeyData
    ]

    let status = SecItemAdd(query as CFDictionary, nil)

    switch status {
    case errSecSuccess:
      break
    case errSecDuplicateItem:
      // Update existing item
      try updateSSHPrivateKey(for: serverID, privateKeyData: privateKeyData)
    default:
      throw KeychainError.unhandledError(status: status)
    }
  }

  public static func loadSSHPrivateKey(for serverID: String) throws -> Data {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "ssh-privatekey-\(serverID)",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    switch status {
    case errSecSuccess:
      guard let keyData = result as? Data else {
        throw KeychainError.unexpectedPasswordData
      }
      return keyData
    case errSecItemNotFound:
      throw KeychainError.itemNotFound
    default:
      throw KeychainError.unhandledError(status: status)
    }
  }

  private static func updateSSHPrivateKey(for serverID: String, privateKeyData: Data) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "ssh-privatekey-\(serverID)"
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: privateKeyData
    ]

    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    guard status == errSecSuccess else {
      throw KeychainError.unhandledError(status: status)
    }
  }

  public static func deleteSSHPrivateKey(for serverID: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "ssh-privatekey-\(serverID)"
    ]

    let status = SecItemDelete(query as CFDictionary)

    switch status {
    case errSecSuccess, errSecItemNotFound:
      break  // Success or item didn't exist
    default:
      throw KeychainError.unhandledError(status: status)
    }
  }

#endif

  // MARK: - Cleanup

  public static func deleteAllSSHCredentials(for serverID: String) throws {
    try deleteSSHPassword(for: serverID)
    try deleteSSHPrivateKey(for: serverID)
  }
}
