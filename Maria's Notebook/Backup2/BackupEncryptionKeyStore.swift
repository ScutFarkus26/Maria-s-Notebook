// BackupEncryptionKeyStore.swift
// Manages the symmetric key that encrypts backup archives (format v19+).
//
// The key lives in the user's iCloud Keychain (kSecAttrSynchronizable) so a
// backup written on one device can be restored on any device signed into the
// same Apple ID — including a brand-new device after the old one is lost,
// which is exactly the scenario backups exist for. A local-only Keychain key
// would make every backup unreadable precisely when it's needed most.
//
// kSecAttrAccessibleAfterFirstUnlock so scheduled and background backups can
// run while the device is locked (after the first unlock since boot).

import Foundation
import CryptoKit
import Security

enum BackupEncryptionKeyStore {

    enum KeyStoreError: LocalizedError {
        case keychainRead(OSStatus)
        case keychainWrite(OSStatus)
        case keyUnavailableForRestore

        var errorDescription: String? {
            switch self {
            case .keychainRead(let status):
                return "Could not read the backup encryption key from the Keychain (error \(status))."
            case .keychainWrite(let status):
                return "Could not save the backup encryption key to the Keychain (error \(status))."
            case .keyUnavailableForRestore:
                return "This backup is encrypted, but its encryption key isn't on this device yet. " +
                    "Make sure this device is signed into the same Apple ID with iCloud Keychain " +
                    "enabled, wait a moment for it to sync, then try again."
            }
        }
    }

    private static let service = "DanielSDeBerry.MariasNoteBook.backup-encryption"
    private static let account = "backup-archive-key-v1"

    /// Returns the existing key, creating and storing a new 256-bit key on
    /// first use. Export paths use this.
    static func fetchOrCreateKey() throws -> SymmetricKey {
        if let key = try fetchKey() { return key }

        let key = SymmetricKey(size: .bits256)
        var attributes = baseQuery
        attributes[kSecAttrSynchronizable as String] = true
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return key
        case errSecDuplicateItem:
            // Another device or process stored a key between our fetch and add —
            // theirs wins, since their backups are already encrypted with it.
            if let existing = try fetchKey() { return existing }
            throw KeyStoreError.keychainWrite(status)
        default:
            throw KeyStoreError.keychainWrite(status)
        }
    }

    /// Returns the key if present, nil when no key exists yet (e.g. a fresh
    /// device whose iCloud Keychain hasn't synced).
    static func fetchKey() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeyStoreError.keychainRead(status) }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeyStoreError.keychainRead(status)
        }
    }

    /// Restore paths use this: throws a user-actionable error when the key is
    /// missing instead of failing deep inside stream setup.
    static func requireKey() throws -> SymmetricKey {
        guard let key = try fetchKey() else {
            throw KeyStoreError.keyUnavailableForRestore
        }
        return key
    }

    /// Matches both synchronizable and (defensively) local items so a key is
    /// never missed because of the synchronizable flag on the query.
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
    }
}
