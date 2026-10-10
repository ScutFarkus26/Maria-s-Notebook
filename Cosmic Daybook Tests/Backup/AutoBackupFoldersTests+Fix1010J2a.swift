import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #83: every device's automatic backups shared one
// `Auto/` folder and one "keep 10", so an iPad on the charger could leave the
// Mac's history only a couple of hours deep. Each device now writes to and
// trims a folder of its own inside `Auto/`; Restore last automatic backup
// looks across every device's folder and the files older builds left at the
// top of `Auto/`, which stay put and are trimmed under the old keep-N rule.
@Suite("Auto backups per device (Fix1010 J2a)", .serialized)
@MainActor
struct AutoBackupFoldersFix1010J2aTests {

    // MARK: - Fixtures

    /// A scratch `Auto/` folder, removed afterwards.
    private static func withAutoFolder(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoBackupFolders-\(UUID().uuidString)", isDirectory: true)
        let auto = root.appendingPathComponent(AutoBackupFolders.autoFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: auto, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(auto)
    }

    /// A device's own defaults, empty, removed afterwards by the caller.
    private static func deviceDefaults() throws -> (UserDefaults, String) {
        let suite = "Fix1010J2a-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// Writes `count` backup files named `prefix-<n>` into `folder`, the
    /// first made `count` hours before the second and so on, all well in the
    /// past (so a backup written now is the newest).
    @discardableResult
    private static func seed(
        _ count: Int, named prefix: String = "AutoBackup", in folder: URL, hoursBack: Int = 1_000
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let start = Date().addingTimeInterval(-Double(hoursBack) * 3_600)
        return try (0..<count).map { index in
            let url = folder.appendingPathComponent("\(prefix)-\(index).\(BackupFile.fileExtension)")
            try Data("backup \(index)".utf8).write(to: url)
            try stamp(url, start.addingTimeInterval(Double(index) * 3_600))
            return url
        }
    }

    private static func stamp(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    }

    /// The same file however the temporary folder's path is spelled.
    private static func path(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private static func names(in folder: URL, prefix: String = "AutoBackup-") throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(prefix) })
    }

    private static func manager(defaults: UserDefaults, autoFolder: URL) -> AutoBackupManager {
        AutoBackupManager(
            coordinator: BackupCoordinator(
                backupService: BackupService(),
                transactionManager: BackupTransactionManager(),
                appRouter: AppRouter()
            ),
            deviceDefaults: defaults,
            autoFolder: autoFolder
        )
    }

    /// The keep-N setting the managers read (Settings › Automatic backups).
    private static var retention: Int {
        UserDefaults.standard.object(forKey: UserDefaultsKeys.autoBackupRetentionCount) as? Int ?? 10
    }

    // MARK: - This device's folder

    @Test("A device's folder name is made once, kept in its own defaults only, and differs between devices")
    func deviceFolderNameIsLocalAndStable() throws {
        let (mac, macSuite) = try Self.deviceDefaults()
        let (pad, padSuite) = try Self.deviceDefaults()
        defer {
            UserDefaults.standard.removePersistentDomain(forName: macSuite)
            UserDefaults.standard.removePersistentDomain(forName: padSuite)
        }

        let macName = AutoBackupFolders.deviceFolderName(defaults: mac, kind: "Mac")
        #expect(macName.hasPrefix("Mac-"))
        #expect(AutoBackupFolders.deviceFolderName(defaults: mac, kind: "Mac") == macName, "the same ever after")
        #expect(AutoBackupFolders.deviceFolderName(defaults: mac, kind: "iPad") == macName, "kind read only once")
        #expect(mac.string(forKey: AutoBackupFolders.deviceFolderKey) == macName)

        let padName = AutoBackupFolders.deviceFolderName(defaults: pad, kind: "iPad")
        #expect(padName.hasPrefix("iPad-"))
        #expect(padName != macName)

        // Never carried to another device: not synced, not backed up, not transferred.
        let key = AutoBackupFolders.deviceFolderKey
        #expect(!SyncedPreferencesStore.syncedKeys.contains(key))
        #expect(!SyncedPreferencesStore.syncedKeyPrefixes.contains { key.hasPrefix($0) })
        #expect(!BackupPreferencesService.isBackedUp(key))
        #expect(!SettingsExportService.transferKeys.contains(key))
    }

    @Test("A stored name that isn't one plain folder name is replaced")
    func unusableNameIsReplaced() throws {
        let (defaults, suite) = try Self.deviceDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        for bad in ["", "..", "a/b", ".hidden", "AutoBackup-x"] {
            defaults.set(bad, forKey: AutoBackupFolders.deviceFolderKey)
            let name = AutoBackupFolders.deviceFolderName(defaults: defaults, kind: "Mac")
            #expect(name != bad && name.hasPrefix("Mac-"), "\(bad.debugDescription) → \(name)")
        }
    }

    // MARK: - Writing and trimming

    @Test("A backup lands in this device's folder; it trims its own and the old top-level files, never another's")
    func backupTrimsOnlyItsOwnFolder() async throws {
        let (defaults, suite) = try Self.deviceDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let keep = Self.retention
        try await Self.withAutoFolder { auto in
            let mine = AutoBackupFolders.deviceFolder(
                in: auto, named: AutoBackupFolders.deviceFolderName(defaults: defaults, kind: "Mac")
            )
            let theirs = auto.appendingPathComponent("iPad-OTHER0", isDirectory: true)
            let ownOld = try Self.seed(keep + 2, in: mine)
            let theirsOld = try Self.seed(keep + 2, in: theirs)
            let topOld = try Self.seed(keep + 2, in: auto)
            let theirManual = try Self.seed(1, named: "ManualBackup", in: theirs)

            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            CoreDataTestHelpers.seedStudent(in: stack.viewContext, firstName: "Ada", lastName: "Lovelace")
            #expect(CoreDataTestHelpers.save(stack.viewContext))

            let result = await Self.manager(defaults: defaults, autoFolder: auto)
                .performManualBackup(viewContext: stack.viewContext)
            guard case .success(_, let written) = result else {
                Issue.record("the backup wasn't written: \(result)")
                return
            }

            // Written into this device's folder, not the top of Auto/.
            #expect(Self.path(written.deletingLastPathComponent()) == Self.path(mine))
            #expect(FileManager.default.fileExists(atPath: written.path))
            // Its own automatic backups trimmed to keep-N, oldest first.
            #expect(try Self.names(in: mine) == Set(ownOld.dropFirst(2).map(\.lastPathComponent)))
            // Another device's folder untouched, manual backup and all.
            #expect(try Self.names(in: theirs) == Set(theirsOld.map(\.lastPathComponent)))
            #expect(FileManager.default.fileExists(atPath: theirManual[0].path))
            // The files older builds left at the top: kept where they are, keep-N.
            #expect(try Self.names(in: auto) == Set(topOld.dropFirst(2).map(\.lastPathComponent)))
        }
    }

    @Test("Two devices sharing one Auto folder never trim each other's backups")
    func twoDevicesKeepTheirOwnHistory() async throws {
        let (mac, macSuite) = try Self.deviceDefaults()
        let (pad, padSuite) = try Self.deviceDefaults()
        defer {
            UserDefaults.standard.removePersistentDomain(forName: macSuite)
            UserDefaults.standard.removePersistentDomain(forName: padSuite)
        }
        let keep = Self.retention
        try await Self.withAutoFolder { auto in
            let macFolder = AutoBackupFolders.deviceFolder(
                in: auto, named: AutoBackupFolders.deviceFolderName(defaults: mac, kind: "Mac")
            )
            let padFolder = AutoBackupFolders.deviceFolder(
                in: auto, named: AutoBackupFolders.deviceFolderName(defaults: pad, kind: "iPad")
            )
            try Self.seed(keep, in: macFolder)
            try Self.seed(keep, in: padFolder)

            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let padManager = Self.manager(defaults: pad, autoFolder: auto)
            // The iPad on the charger backs up again and again: each round one
            // more automatic backup, then a run that trims (any trigger does).
            for round in 0..<3 {
                try Self.seed(1, named: "AutoBackup-pad\(round)", in: padFolder, hoursBack: 0)
                CoreDataTestHelpers.seedStudent(in: stack.viewContext, firstName: "Child\(round)", lastName: "Pad")
                #expect(CoreDataTestHelpers.save(stack.viewContext))
                let result = await padManager.performManualBackup(viewContext: stack.viewContext)
                guard case .success = result else {
                    Issue.record("round \(round): \(result)")
                    return
                }
                #expect(try Self.names(in: padFolder).count == keep, "round \(round)")
            }

            // …and the Mac's history is all still there.
            #expect(try Self.names(in: macFolder).count == keep)
            #expect(try Self.names(in: padFolder).count == keep)
        }
    }

    // MARK: - Finding the latest

    @Test("Restore last automatic backup finds the newest across every device's folder and the old top-level files")
    func mostRecentLooksAcrossFolders() async throws {
        try await Self.withAutoFolder { auto in
            let mac = auto.appendingPathComponent("Mac-AAAA0000", isDirectory: true)
            let pad = auto.appendingPathComponent("iPad-BBBB0000", isDirectory: true)
            let topOld = try Self.seed(1, named: "AutoBackup-top", in: auto, hoursBack: 50)[0]
            let macLatest = try Self.seed(1, named: "AutoBackup-mac", in: mac, hoursBack: 10)[0]
            try Self.seed(1, named: "AutoBackup-pad", in: pad, hoursBack: 20)
            // Not candidates, though newer: a file that isn't a backup, and a
            // backup two folders down.
            let note = mac.appendingPathComponent("Read me.txt")
            try Data("x".utf8).write(to: note)
            try Self.stamp(note, Date())
            try Self.seed(1, named: "AutoBackup-deeper", in: pad.appendingPathComponent("Old"), hoursBack: 1)

            let latest = try #require(AutoBackupFolders.mostRecentBackup(in: [auto]))
            #expect(Self.path(latest) == Self.path(macLatest), "another device's folder is looked in")
            #expect(AutoBackupFolders.backupFiles(in: auto).count == 3)

            // An old build's file at the top is listed too, and wins when newest.
            try Self.stamp(topOld, Date())
            #expect(AutoBackupFolders.mostRecentBackup(in: [auto]).map(Self.path) == Self.path(topOld))

            // And across both places automatic backups have lived.
            let other = auto.deletingLastPathComponent().appendingPathComponent("Fallback", isDirectory: true)
            let newest = try Self.seed(1, named: "ScheduledBackup", in: other.appendingPathComponent("Mac-CCCC0000"))[0]
            try Self.stamp(newest, Date().addingTimeInterval(60))
            #expect(AutoBackupFolders.mostRecentBackup(in: [auto, other]).map(Self.path) == Self.path(newest))
            #expect(AutoBackupFolders.mostRecentBackup(in: [auto.appendingPathComponent("Missing")]) == nil)
        }
    }
}
