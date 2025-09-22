import Foundation
import OpenCoderCore

extension StorageClient {
    package static let liveValue = StorageClient(
        data: { key in
            UserDefaults.standard.data(forKey: key)
        },
        setData: { data, key in
            UserDefaults.standard.set(data, forKey: key)
        },
        string: { key in
            UserDefaults.standard.string(forKey: key)
        },
        setString: { string, key in
            UserDefaults.standard.set(string, forKey: key)
        },
        bool: { key in
            UserDefaults.standard.bool(forKey: key)
        },
        setBool: { bool, key in
            UserDefaults.standard.set(bool, forKey: key)
        },
        integer: { key in
            UserDefaults.standard.integer(forKey: key)
        },
        setInteger: { integer, key in
            UserDefaults.standard.set(integer, forKey: key)
        }
    )
}