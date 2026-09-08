//
//  Keychain.swift
//  Heart Rate Monitor
//

import Foundation
import Security

// Credential storage. Unlike UserDefaults the contents are encrypted at rest and
// stay on this device rather than travelling in backups.
enum Keychain {

    static func string(forKey key: String) -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            query(key, [kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]), &item
        )
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, forKey key: String) {
        guard let data = value?.data(using: .utf8) else {
            SecItemDelete(query(key))
            return
        }
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query(key), attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query(key, attributes), nil)
        }
    }

    private static func query(_ key: String, _ extra: [CFString: Any] = [:]) -> CFDictionary {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "HeartRateMonitor",
            kSecAttrAccount: key,
        ]
        query.merge(extra) { _, new in new }
        return query as CFDictionary
    }
}
