import Foundation

public protocol AppColorProvider {
    associatedtype ColorType
    var green: ColorType { get }
    var red: ColorType { get }
}

 public enum AppColorType: String, Codable, CaseIterable, Sendable {

     case green
     case red

     public var displayName: String {
         switch self {
         case .green: return "Green"
         case .red: return "Red"
         }
     }
 }
