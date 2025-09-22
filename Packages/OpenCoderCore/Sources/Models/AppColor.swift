import Foundation

package protocol AppColorProvider {
    associatedtype ColorType
    var green: ColorType { get }
    var red: ColorType { get }
}

package enum AppColorType: String, Codable, CaseIterable {
    case green
    case red
    
    package var displayName: String {
        switch self {
        case .green: return "Green"
        case .red: return "Red"
        }
    }
}