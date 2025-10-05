import SwiftUI
import OpenCoderCore

public extension AppColorType {
    var color: Color {
        switch self {
        case .green:
            return .green
        case .red:
            return .red
        }
    }
}

 public extension ActivityEvent.EventType {
     var color: Color {
         return self.colorType.color
     }
 }

 struct WorkspaceRemotePathKey: EnvironmentKey {
     static let defaultValue: String? = nil
 }

 extension EnvironmentValues {
     var workspaceRemotePath: String? {
         get { self[WorkspaceRemotePathKey.self] }
         set { self[WorkspaceRemotePathKey.self] = newValue }
     }
 }
