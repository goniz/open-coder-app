import SwiftUI
import OpenCoderCore

package extension AppColorType {
    var color: Color {
        switch self {
        case .green:
            return .green
        case .red:
            return .red
        }
    }
}

package extension ActivityEvent.EventType {
    var color: Color {
        return self.colorType.color
    }
}