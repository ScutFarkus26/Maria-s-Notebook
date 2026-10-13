import Foundation
import Security

/// Where a ParentLocker sign-in is kept: only in the Keychain, never in Core
/// Data, the classroom share, backups, preferences or logs (plan "ParentLocker
/// attendance", Privacy rules; Apple guidance, item 1). Two items per site:
///
/// - **The password**, an internet password for the site's host over HTTPS,
///   synced through the person's own iCloud Keychain
///   (`kSecAttrSynchronizable`), so one sign-in covers all of Danny's
///   devices and each assistant's stays hers. End-to-end encrypted by Apple.
///   Readable after the first unlock, so a sync from the background can sign
///   back in. Deleting it deletes every synced copy (Sign Out everywhere).
/// - **The site's cookies**, a generic password on this device only
///   (`…AfterFirstUnlockThisDeviceOnly`, never synced, never in a device
///   backup).
///
/// Follows `BackupEncryptionKeyStore`'s pattern (which isn't in the Daybook
/// Assistant), with every query matching synced and local copies alike, and
/// the data-protection keychain on the Mac (TN3137).
nonisolated enum ParentLockerKeychain {

    /// A ParentLocker sign-in. Its description never shows the password.
    struct Credential: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
        let email: String
        let password: String

        init(email: String, password: String) {
            self.email = email
            self.password = password
        }

        var description: String { "ParentLocker sign-in (hidden)" }
        var debugDescription: String { description }
    }

    enum KeychainError: LocalizedError, Equatable {
        case read(OSStatus)
        case write(OSStatus)

        /// What the person reads; the status goes to the log where it's caught.
        var errorDescription: String? {
            switch self {
            case .read:
                "Couldn't read your saved ParentLocker sign-in on this device. Restart the device and try again."
            case .write:
                "Couldn't save your ParentLocker sign-in on this device. Try again."
            }
        }
    }

    /// The cookie item's service; its account is the site's host.
    private static let cookieService = "DanielSDeBerry.MariasNoteBook.parentlocker-cookies"

    // MARK: - Password (synced)

    /// Saves the sign-in for `site`, replacing the one there (on every device).
    static func savePassword(_ credential: Credential, site: String) throws {
        let data = Data(credential.password.utf8)
        let changes: [String: Any] = [
            kSecAttrAccount as String: credential.email,
            kSecValueData as String: data
        ]
        // Update in place, so another device checking that the password is
        // still there never sees it gone in between.
        let status = SecItemUpdate(passwordQuery(site: site) as CFDictionary, changes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            try addPassword(credential, data: data, site: site)
        case errSecDuplicateItem:
            // Two items under different emails: start again with one.
            try deletePassword(site: site)
            try addPassword(credential, data: data, site: site)
        default:
            throw KeychainError.write(status)
        }
    }

    private static func addPassword(_ credential: Credential, data: Data, site: String) throws {
        var attributes = baseAttributes
        attributes[kSecClass as String] = kSecClassInternetPassword
        attributes[kSecAttrServer as String] = host(site)
        attributes[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
        attributes[kSecAttrAccount as String] = credential.email
        attributes[kSecAttrSynchronizable as String] = true
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecAttrLabel as String] = host(site)
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.write(status) }
    }

    /// The saved sign-in for `site`, or nil when there is none (never signed
    /// in, signed out, or not synced to this device yet).
    static func credential(site: String) throws -> Credential? {
        var query = passwordQuery(site: site)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let found = item as? [String: Any],
                  let data = found[kSecValueData as String] as? Data,
                  let password = String(bytes: data, encoding: .utf8) else { throw KeychainError.read(status) }
            return Credential(email: found[kSecAttrAccount as String] as? String ?? "", password: password)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.read(status)
        }
    }

    /// Whether a sign-in is saved for `site`, without reading the password:
    /// the check before each sync that Sign Out on another device hasn't
    /// removed it.
    static func hasPassword(site: String) throws -> Bool {
        var query = passwordQuery(site: site)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw KeychainError.read(status)
        }
    }

    /// Deletes the sign-in for `site` here and, through iCloud Keychain, on
    /// every other device of the person's. Nothing there is fine.
    static func deletePassword(site: String) throws {
        let status = SecItemDelete(passwordQuery(site: site) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.write(status) }
    }

    /// Every copy of the site's password item, synced or not, under any email.
    private static func passwordQuery(site: String) -> [String: Any] {
        var query = baseAttributes
        query[kSecClass as String] = kSecClassInternetPassword
        query[kSecAttrServer as String] = host(site)
        query[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        return query
    }

    // MARK: - Cookies (this device only)

    /// Saves the site's cookies on this device, replacing those there. An
    /// empty list deletes them.
    static func saveCookies(_ cookies: [ParentLockerCookie], site: String) throws {
        guard !cookies.isEmpty else { return try deleteCookies(site: site) }
        let data: Data
        do {
            data = try JSONEncoder().encode(cookies)
        } catch {
            throw KeychainError.write(errSecParam)
        }
        let status = SecItemUpdate(
            cookieQuery(site: site) as CFDictionary, [kSecValueData as String: data] as CFDictionary
        )
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = cookieQuery(site: site)
            attributes[kSecAttrSynchronizable as String] = false
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes[kSecValueData as String] = data
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.write(added) }
        default:
            throw KeychainError.write(status)
        }
    }

    /// The cookies saved on this device for `site`; none when there are none.
    static func cookies(site: String) throws -> [ParentLockerCookie] {
        var query = cookieQuery(site: site)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let cookies = try? JSONDecoder().decode([ParentLockerCookie].self, from: data) else {
                throw KeychainError.read(status)
            }
            return cookies
        case errSecItemNotFound:
            return []
        default:
            throw KeychainError.read(status)
        }
    }

    static func deleteCookies(site: String) throws {
        let status = SecItemDelete(cookieQuery(site: site) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.write(status) }
    }

    private static func cookieQuery(site: String) -> [String: Any] {
        var query = baseAttributes
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrService as String] = cookieService
        query[kSecAttrAccount as String] = host(site)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        return query
    }

    // MARK: - Shared

    /// What every query and item carries: on the Mac, the data-protection
    /// keychain (the iOS-style one) rather than the old file keychain.
    private static var baseAttributes: [String: Any] {
        #if os(macOS)
        [kSecUseDataProtectionKeychain as String: true]
        #else
        [:]
        #endif
    }

    private static func host(_ site: String) -> String {
        AttendanceEmailLog.parentLockerHost(site)
    }
}
