import Dependencies
import Protocols

extension SSHClient: DependencyKey {
  public static let liveValue = SSHClient()
}
