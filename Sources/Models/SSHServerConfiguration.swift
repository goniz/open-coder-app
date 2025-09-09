import Foundation

package struct SSHServerConfiguration: Equatable, Codable {
  package var name: String
  package var host: String
  package var port: Int
  package var username: String
  package var password: String
  package var useKeyAuthentication: Bool
  package var privateKeyPath: String
  package var shouldMaintainConnection: Bool

  package init(
    name: String = "",
    host: String = "",
    port: Int = 22,
    username: String = "",
    password: String = "",
    useKeyAuthentication: Bool = false,
    privateKeyPath: String = "",
    shouldMaintainConnection: Bool = false
  ) {
    self.name = name
    self.host = host
    self.port = port
    self.username = username
    self.password = password
    self.useKeyAuthentication = useKeyAuthentication
    self.privateKeyPath = privateKeyPath
    self.shouldMaintainConnection = shouldMaintainConnection
  }

  package var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    port > 0 && port <= 65535 &&
    (useKeyAuthentication ? !privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !password.isEmpty)
  }
}
