import Foundation
import Security

/// Stores the ThinQ Personal Access Token in the login keychain.
enum Keychain {
    private static let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ac-bar",
        kSecAttrAccount as String: "thinq-pat",
    ]

    static func get() -> String? {
        var query = item
        query[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String) {
        SecItemDelete(item as CFDictionary)
        var query = item
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }
}
