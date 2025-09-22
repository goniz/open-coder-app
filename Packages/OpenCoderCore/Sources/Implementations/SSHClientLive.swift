import Dependencies
import Protocols

extension SSHClient: DependencyKey {
  package static let liveValue = SSHClient()
}
