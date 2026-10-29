import Foundation
import OSLog
import Security
#if canImport(UIKit)
import UIKit
#endif

/// Where automatic backups live inside the backup folder's `Auto/`: each
/// device writes to, and trims, a folder of its own, named by an ID kept on
/// that device only.
///
/// Until 2026-10-10 every device wrote straight into `Auto/` under one shared
/// "keep 10", so an iPad on the charger (a backup every 15 minutes) could
/// leave the Mac's backups only a couple of hours deep (bug hunt P2 #83).
/// Restore last automatic backup and the backup status still look across
/// every device's folder, and across the files older builds left at the top
/// of `Auto/`: those stay where they are and are trimmed under the old
/// keep-N rule. `BackupFolderMigration` is unchanged.
nonisolated enum AutoBackupFolders {
    private static let logger = Logger.backup

    /// The folder automatic backups go in, inside the backup folder.
    static let autoFolderName = "Auto"

    /// The automatic backups' file names, the only files trimming removes.
    /// Manual backups (`ManualBackup-`) go in the same folder and are kept.
    static let trimmedPrefixes = ["AutoBackup-", "ScheduledBackup-", "PreOp-"]

    // MARK: - This device's folder

    /// Where this device keeps its folder's name. In the device's own
    /// defaults only: not synced (`SyncedPreferencesStore`), not in a backup
    /// (`BackupPreferencesService`) and not in a settings transfer, so no
    /// other device ever writes to or trims this device's folder.
    ///
    /// A device set up from another's device backup (a new iPhone restored
    /// from the old one's, a Mac from Migration Assistant) gets that device's
    /// defaults, this name included, so the two shared one folder and each
    /// trimmed the other's backups (bug hunt 2026-10-29). The name is marked
    /// as this device's in the Keychain too (`DeviceMark`), which a device
    /// backup never carries to another device.
    static let deviceFolderKey = "AutoBackup.deviceFolderName"

    /// Set in the defaults once the name is marked in the Keychain. Defaults
    /// that say so on a device with no mark came from another device.
    static let deviceFolderMarkedKey = "AutoBackup.deviceFolderMarked"

    /// Where a device notes, on itself alone, which folder name is its own.
    struct DeviceMark: Sendable {
        /// The name noted on this device; nil when none is; throws when it
        /// can't be read (a Keychain still locked after a restart).
        let read: @Sendable () throws -> String?
        let write: @Sendable (String) throws -> Void

        /// The app's: a Keychain item on this device only.
        static let keychain = DeviceMark(read: AutoBackupFolderMark.read, write: AutoBackupFolderMark.save)
    }

    /// This device's folder name inside `Auto/` ("iPad-1A2B3C4D"), made the
    /// first time it's asked for and the same ever after. `kind` names the
    /// device in Files; it is used only when the name is first made. A name
    /// copied from another device is replaced by one of this device's own.
    static func deviceFolderName(
        defaults: UserDefaults = .standard, kind: String, mark: DeviceMark = .keychain
    ) -> String {
        let stored = defaults.string(forKey: deviceFolderKey).flatMap { isUsableFolderName($0) ? $0 : nil }
        let marked: String?
        do {
            marked = try mark.read().flatMap { isUsableFolderName($0) ? $0 : nil }
        } catch {
            logger.warning("Couldn't read this device's backup folder mark: \(error.localizedDescription)")
            // Can't tell whose the name is: go on where this device has been writing.
            if let stored { return stored }
            marked = nil
        }
        if let marked {
            // The Keychain's name is this device's (the defaults may have
            // been cleared, as when the app was deleted and put back).
            if marked != stored { defaults.set(marked, forKey: deviceFolderKey) }
            return marked
        }
        if let stored, !defaults.bool(forKey: deviceFolderMarkedKey) {
            // Named before names were marked: this device's own.
            markAsThisDevice(stored, defaults: defaults, mark: mark)
            return stored
        }
        let shortID = UUID().uuidString.prefix(8)
        let name = "\(kind)-\(shortID)"
        defaults.set(name, forKey: deviceFolderKey)
        markAsThisDevice(name, defaults: defaults, mark: mark)
        return name
    }

    /// Marks `name` as this device's. If the Keychain won't take it, the
    /// defaults aren't flagged either, so the name is kept and marked later.
    private static func markAsThisDevice(_ name: String, defaults: UserDefaults, mark: DeviceMark) {
        do {
            try mark.write(name)
            defaults.set(true, forKey: deviceFolderMarkedKey)
        } catch {
            logger.warning("Couldn't mark this device's backup folder: \(error.localizedDescription)")
        }
    }

    /// The kind of device this is, for its folder's name.
    @MainActor
    static func currentDeviceKind() -> String {
        #if os(macOS)
        return "Mac"
        #elseif os(visionOS)
        return "Vision"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    static func deviceFolder(in autoFolder: URL, named name: String) -> URL {
        autoFolder.appendingPathComponent(name, isDirectory: true)
    }

    /// A stored name that is one plain folder name, never a path or one
    /// trimming would take for a backup file.
    private static func isUsableFolderName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.hasPrefix(".") && !name.contains("/")
            && !trimmedPrefixes.contains { name.hasPrefix($0) }
    }

    // MARK: - Trimming

    /// After a backup: keeps the newest `count` automatic backups in this
    /// device's folder, and the newest `count` of those older builds left at
    /// the top of `Auto/`. Another device's folder is never touched.
    static func trimAfterBackup(
        autoFolder: URL,
        deviceFolder: URL,
        keeping count: Int,
        delete: (URL) throws -> Void = UbiquitousFile.coordinatedDelete
    ) {
        trim(deviceFolder, keeping: count, delete: delete)
        trim(autoFolder, keeping: count, delete: delete)
    }

    /// Deletes the oldest automatic backups directly inside `folder` (by
    /// creation date) until `count` are left. Subfolders, manual backups and
    /// other files stay. Never fewer than one, so the backup just written
    /// survives a keep-0 setting.
    static func trim(
        _ folder: URL,
        keeping count: Int,
        delete: (URL) throws -> Void = UbiquitousFile.coordinatedDelete
    ) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.warning("Failed to list directory contents: \(error)")
            return
        }

        let autoBackups = files.filter { url in
            let name = url.lastPathComponent
            return trimmedPrefixes.contains { name.hasPrefix($0) } && !isDirectory(url)
        }
        let oldestFirst = autoBackups.sorted { creationDate(of: $0) < creationDate(of: $1) }

        let keep = max(count, 1)
        guard oldestFirst.count > keep else { return }
        for url in oldestFirst.prefix(oldestFirst.count - keep) {
            do {
                // Coordinated: the folder is usually in iCloud Drive.
                try delete(url)
            } catch {
                logger.warning("Failed to delete old backup \(url.lastPathComponent): \(error)")
            }
        }
    }

    // MARK: - Listing

    /// Every backup file in `autoFolder`: those at its top (where older
    /// builds wrote) and those one level down, in each device's folder.
    static func backupFiles(in autoFolder: URL) -> [URL] {
        let entries = contents(of: autoFolder)
        var files = entries.filter { $0.pathExtension == BackupFile.fileExtension && !isDirectory($0) }
        for folder in entries where isDirectory(folder) {
            files += contents(of: folder).filter { $0.pathExtension == BackupFile.fileExtension && !isDirectory($0) }
        }
        return files
    }

    /// The newest backup by modification date across `autoFolders`, whichever
    /// device made it, or nil when there is none.
    static func mostRecentBackup(in autoFolders: [URL]) -> URL? {
        autoFolders
            .flatMap(backupFiles(in:))
            .max { modificationDate(of: $0) < modificationDate(of: $1) }
    }

    // MARK: - File details

    private static func contents(of folder: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        do {
            return try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.warning("Failed to list directory contents: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func creationDate(of url: URL) -> Date {
        do {
            return try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
        } catch {
            logger.warning("Failed to get creation date for \(url.lastPathComponent): \(error)")
            return .distantPast
        }
    }

    private static func modificationDate(of url: URL) -> Date {
        do {
            return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                ?? .distantPast
        } catch {
            let name = url.lastPathComponent
            let desc = error.localizedDescription
            logger.warning("Failed to get mod date for \(name, privacy: .public): \(desc, privacy: .public)")
            return .distantPast
        }
    }
}

/// The Keychain item that marks an automatic-backup folder name as this
/// device's (`AutoBackupFolders.DeviceMark`): a generic password on this
/// device only (`…AfterFirstUnlockThisDeviceOnly`, never synced, never
/// carried to another device by a device backup), on the Mac in the
/// data-protection keychain, as `TideKeychain` keeps its item.
nonisolated private enum AutoBackupFolderMark {
    private static let service = "DanielSDeBerry.MariasNoteBook.auto-backup-folder"
    private static let account = "device-folder"

    struct KeychainError: Error {
        let status: OSStatus
    }

    static func read() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let name = String(bytes: data, encoding: .utf8) else {
                throw KeychainError(status: status)
            }
            return name
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    static func save(_ name: String) throws {
        let data = Data(name.utf8)
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
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        default:
            throw KeychainError(status: status)
        }
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
