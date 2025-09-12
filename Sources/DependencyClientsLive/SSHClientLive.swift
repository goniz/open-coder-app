import Dependencies
import DependencyClients

extension SSHClient: DependencyKey {
  package static let liveValue = SSHClient()
}
