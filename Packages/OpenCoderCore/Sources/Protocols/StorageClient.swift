import Dependencies
import Foundation

public struct StorageClient: Sendable {
    public var data: @Sendable (String) -> Data?
    public var setData: @Sendable (Data?, String) -> Void
    public var string: @Sendable (String) -> String?
    public var setString: @Sendable (String?, String) -> Void
    public var bool: @Sendable (String) -> Bool
    public var setBool: @Sendable (Bool, String) -> Void
    public var integer: @Sendable (String) -> Int
    public var setInteger: @Sendable (Int, String) -> Void

     public init(
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
    public static let liveValue = StorageClient(
        data: { key in
            UserDefaults.standard.data(forKey: key)
        },
        setData: { data, key in
            if let data {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        },
        string: { key in
            UserDefaults.standard.string(forKey: key)
        },
        setString: { string, key in
            if let string {
                UserDefaults.standard.set(string, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        },
        bool: { key in
            if UserDefaults.standard.object(forKey: key) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: key)
        },
        setBool: { bool, key in
            UserDefaults.standard.set(bool, forKey: key)
        },
        integer: { key in
            if UserDefaults.standard.object(forKey: key) == nil {
                return 0
            }
            return UserDefaults.standard.integer(forKey: key)
        },
        setInteger: { integer, key in
            UserDefaults.standard.set(integer, forKey: key)
        }
    )

    public static let testValue = StorageClient(
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
    public var storage: StorageClient {
        get { self[StorageClient.self] }
        set { self[StorageClient.self] = newValue }
    }
}
