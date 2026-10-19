// TideKeychain.swift
// Where Tide's connection address is kept.

import Foundation
import Security

/// Tide's connection address, in the Keychain only: it holds Tide's token,
/// which lets whoever has it change Danny's to-dos. A generic password on this
/// Mac only (`…AfterFirstUnlockThisDeviceOnly`, never synced, never in a
/// device backup, never in the notebook's backups or preferences): the token
/// is this Mac's Tide's, and only the Mac's notebook talks to Tide.
///
/// Follows `ParentLockerKeychain`'s pattern (its sign-in cookies are the same
/// kind of item), with the data-protection keychain on the Mac (TN3137).
nonisolated enum TideKeychain {

    enum KeychainError: LocalizedError, Equatable {
        case read(OSStatus)
        case write(OSStatus)

        /// What the person reads; the status goes to the log where it's caught.
        var errorDescription: String? {
            switch self {
            case .read:
                "Couldn't read the saved Tide connection on this Mac. Paste the address again."
            case .write:
                "Couldn't save the Tide connection on this Mac. Try again."
            }
        }
    }

    private static let service = "DanielSDeBerry.MariasNoteBook.tide-connection"
    private static let account = "address"

    /// Saves the address, replacing the one there.
    static func save(_ address: TideAddress) throws {
        let data = Data(address.url.absoluteString.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = query
            attributes[kSecAttrSynchronizable as String] = false
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes[kSecValueData as String] = data
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.write(added) }
        default:
            throw KeychainError.write(status)
        }
    }

    /// The saved address, or nil when none is saved.
    static func address() throws -> TideAddress? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(bytes: data, encoding: .utf8),
                  case .success(let address) = TideAddress.parse(text) else { throw KeychainError.read(status) }
            return address
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.read(status)
        }
    }

    /// Forgets the address. Nothing there is fine.
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.write(status) }
    }

    private static var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}
