// BackupEncryptionKeyStore.swift
// Manages the symmetric keys that encrypt backup archives (format v19+).
//
// The keys live in the user's iCloud Keychain (kSecAttrSynchronizable) so a
// backup written on one device can be restored on any device signed into the
// same Apple ID — including a brand-new device after the old one is lost,
// which is exactly the scenario backups exist for. A local-only Keychain key
// would make every backup unreadable precisely when it's needed most.
//
// kSecAttrAccessibleAfterFirstUnlock so scheduled and background backups can
// run while the device is locked (after the first unlock since boot).
//
// More than one key (bug hunt 2026-11-02 #15). Until 2026-11 there was one
// item, `backup-archive-key-v1`. A new device whose iCloud Keychain hadn't
// synced yet made its own under the same name, and when the first device's
// arrived the two collided: iCloud Keychain keeps one of them, and Apple
// doesn't say which, so every backup made with the other could no longer be
// opened anywhere. Now each key made is an item of its own, its account
// stamped with when it was made (`backup-archive-key-v2.<date>.<UUID>`), so
// no two collide and every one reaches every device. Every key is kept for
// reading (`BackupReader` tries each), and every device writes with the same
// one, the oldest: the v1 key where there is one. No key is made while the
// notebook's first download from iCloud is under way, when the Keychain is
// as likely as the notebook to be still on its way.

import Foundation
import CryptoKit
import Security

nonisolated enum BackupEncryptionKeyStore {

    enum KeyStoreError: LocalizedError {
        case keychainRead(OSStatus)
        case keychainWrite(OSStatus)
        case keyUnavailableForRestore
        /// No key on this device yet, and none is made while the first
        /// download from iCloud is under way: iCloud Keychain is probably
        /// still bringing the one the other devices use.
        case keyNotHereYet

        /// What the guide reads; the Keychain status goes to the log where
        /// the error is caught.
        var errorDescription: String? {
            switch self {
            case .keychainRead, .keychainWrite:
                return "Couldn't unlock this device's backup key. Restart the device and try again."
            case .keyUnavailableForRestore:
                return "This backup is locked with a key that isn't on this device yet. Make sure this " +
                    "device is signed in to the same Apple Account with iCloud Keychain on, wait a " +
                    "moment, then try again."
            case .keyNotHereYet:
                return "This device is still getting your notebook from iCloud, and the key that locks " +
                    "your backups hasn't arrived yet. Try again once the download has finished."
            }
        }
    }

    /// One backup key and the Keychain account that names it.
    struct StoredKey: Sendable {
        let account: String
        let key: SymmetricKey
    }

    /// Where the keys are kept: the Keychain in the app, a stand-in in tests
    /// (`$items.withValue`), which must never touch the real one.
    struct Items: Sendable {
        /// Every backup key item there is, in no particular order.
        let list: @Sendable () throws -> [StoredKey]
        /// Adds a new item. Never replaces one.
        let add: @Sendable (StoredKey) throws -> Void

        static let keychain = Items(list: KeychainItems.list, add: KeychainItems.add)
    }

    /// The keys every call here reads and adds.
    @TaskLocal static var items: Items = .keychain

    /// The item every build before 2026-11 made and wrote with.
    static let legacyAccount = "backup-archive-key-v1"
    private static let stampedAccountPrefix = "backup-archive-key-v2"

    // MARK: - Writing

    /// The key exports encrypt with: the oldest key there is, so every device
    /// writes with the same one once they all have it. Makes one, stamped
    /// with `now`, on first use, but never while `firstDownloadPending`.
    static func fetchOrCreateKey(
        firstDownloadPending: Bool = FirstDownloadGate.isPending(),
        now: Date = Date()
    ) throws -> SymmetricKey {
        if let key = writingKey(in: try items.list()) { return key }
        guard !firstDownloadPending else { throw KeyStoreError.keyNotHereYet }

        let made = StoredKey(account: stampedAccount(madeAt: now), key: SymmetricKey(size: .bits256))
        try items.add(made)
        // An older key that arrived meanwhile is the one to write with.
        return writingKey(in: try items.list()) ?? made.key
    }

    // MARK: - Reading

    /// The key a restore tries first: the one exports write with. Throws a
    /// user-actionable error when there is none instead of failing deep
    /// inside stream setup.
    static func requireKey() throws -> SymmetricKey {
        guard let key = writingKey(in: try items.list()) else {
            throw KeyStoreError.keyUnavailableForRestore
        }
        return key
    }

    /// Every backup key on this device, the writing key first: an archive
    /// the first one can't open is tried with the others (`BackupReader`).
    static func readingKeys() throws -> [SymmetricKey] {
        ordered(try items.list()).map(\.key)
    }

    // MARK: - Order

    /// `keys` oldest first: the v1 key, then the stamped ones by the time in
    /// their names (an account with no readable time last). Ties go by
    /// account, so every device puts the same keys in the same order.
    static func ordered(_ keys: [StoredKey]) -> [StoredKey] {
        keys.sorted { lhs, rhs in
            let left = madeAt(lhs.account), right = madeAt(rhs.account)
            return left == right ? lhs.account < rhs.account : left < right
        }
    }

    private static func writingKey(in keys: [StoredKey]) -> SymmetricKey? {
        ordered(keys).first?.key
    }

    /// A new key's account: `backup-archive-key-v2.<when, ISO 8601>.<UUID>`,
    /// unique, so it never collides with another device's.
    static func stampedAccount(madeAt date: Date) -> String {
        "\(stampedAccountPrefix).\(date.formatted(.iso8601)).\(UUID().uuidString)"
    }

    /// When the key `account` names was made: the distant past for the v1
    /// key, which came first; the distant future for a name this build can't read.
    static func madeAt(_ account: String) -> Date {
        if account == legacyAccount { return .distantPast }
        let parts = account.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == stampedAccountPrefix,
              let date = try? Date(String(parts[1]), strategy: .iso8601) else { return .distantFuture }
        return date
    }
}

/// The backup keys in the Keychain: generic passwords under one service,
/// one account each. Queries match synchronizable and (defensively) local
/// items, so a key is never missed because of the synchronizable flag.
nonisolated private enum KeychainItems {
    private static let service = "DanielSDeBerry.MariasNoteBook.backup-encryption"

    static func list() throws -> [BackupEncryptionKeyStore.StoredKey] {
        // Accounts first, then each one's key: asking for every item's data
        // at once isn't allowed in every keychain.
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return []
        default:
            throw BackupEncryptionKeyStore.KeyStoreError.keychainRead(status)
        }
        let accounts = Set(((items as? [[String: Any]]) ?? []).compactMap { $0[kSecAttrAccount as String] as? String })
        return try accounts.sorted().compactMap { account in
            try key(account: account).map { BackupEncryptionKeyStore.StoredKey(account: account, key: $0) }
        }
    }

    static func add(_ stored: BackupEncryptionKeyStore.StoredKey) throws {
        var attributes = baseQuery
        attributes[kSecAttrAccount as String] = stored.account
        attributes[kSecAttrSynchronizable as String] = true
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecAttrLabel as String] = "Cosmic Daybook backup key"
        attributes[kSecValueData as String] = stored.key.withUnsafeBytes { Data($0) }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw BackupEncryptionKeyStore.KeyStoreError.keychainWrite(status)
        }
    }

    private static func key(account: String) throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecAttrAccount as String] = account
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw BackupEncryptionKeyStore.KeyStoreError.keychainRead(status)
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw BackupEncryptionKeyStore.KeyStoreError.keychainRead(status)
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
    }
}
