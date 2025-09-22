import Dependencies
import Foundation

package struct StorageClient: Sendable {
    package var data: @Sendable (String) -> Data?
    package var setData: @Sendable (Data?, String) -> Void
    package var string: @Sendable (String) -> String?
    package var setString: @Sendable (String?, String) -> Void
    package var bool: @Sendable (String) -> Bool
    package var setBool: @Sendable (Bool, String) -> Void
    package var integer: @Sendable (String) -> Int
    package var setInteger: @Sendable (Int, String) -> Void
    
    package init(
        data: @escaping @Sendable (String) -> Data?,
        setData: @escaping @Sendable (Data?, String) -> Void,
        string: @escaping @Sendable (String) -> String?,
        setString: @escaping @Sendable (String?, String) -> Void,
        bool: @escaping @Sendable (String) -> Bool,
        setBool: @escaping @Sendable (Bool, String) -> Void,
        integer: @escaping @Sendable (String) -> Int,
        setInteger: @escaping @Sendable (Int, String) -> Void
    ) {
        self.data = data
        self.setData = setData
        self.string = string
        self.setString = setString
        self.bool = bool
        self.setBool = setBool
        self.integer = integer
        self.setInteger = setInteger
    }
}

extension StorageClient: DependencyKey {
    package static let testValue = StorageClient(
        data: { _ in nil },
        setData: { _, _ in },
        string: { _ in nil },
        setString: { _, _ in },
        bool: { _ in false },
        setBool: { _, _ in },
        integer: { _ in 0 },
        setInteger: { _, _ in }
    )
}

extension DependencyValues {
    package var storage: StorageClient {
        get { self[StorageClient.self] }
        set { self[StorageClient.self] = newValue }
    }
}