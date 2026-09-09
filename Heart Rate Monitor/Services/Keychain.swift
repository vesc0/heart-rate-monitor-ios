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

    // Replaces rather than updates: SecItemUpdate cannot change kSecAttrAccessible,
    // so an in-place update would silently leave the previous value behind.
    static func set(_ value: String?, forKey key: String) {
        SecItemDelete(query(key))
        guard let data = value?.data(using: .utf8) else { return }
        SecItemAdd(query(key, [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]), nil)
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
