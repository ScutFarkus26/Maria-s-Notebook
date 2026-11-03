import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-02, the backup-writing findings, continued from
// BackupWritingFix1102Tests.swift: automatic backups found and trimmed, the
// manager's partial names and outcomes, the Overview's row, the size estimate.

// MARK: - Finding and trimming automatic backups (#14, #18)

@Suite("Automatic backups found and trimmed (Fix1102 #14 #18)", .serialized)
struct AutoBackupFindingFix1102Tests {

    private static func name(_ prefix: String, _ date: Date) -> String {
        let stamp = DateFormatters.iso8601DateTimeWithFractionalSeconds.string(from: date)
        return "\(prefix)-\(stamp).\(BackupFile.fileExtension)"
    }

    private static func path(_ url: URL?) -> String? {
        url?.resolvingSymlinksInPath().path
    }

    @Test("The newest backup goes by the time in its name, skips partial ones, and counts ones not downloaded here")
    func newestBackup() async throws {
        try await Fix1102Fixtures.withFolder { auto in
            let now = Date()
            let mac = auto.appendingPathComponent("Mac-AAAA0000", isDirectory: true)
            let pad = auto.appendingPathComponent("iPad-BBBB0000", isDirectory: true)
            // Older by name, but touched since (copied, say): the name wins.
            let older = mac.appendingPathComponent(Self.name("AutoBackup", now.addingTimeInterval(-7_200)))
            try Fix1102Fixtures.touch(older, modified: now)
            let newer = mac.appendingPathComponent(Self.name("AutoBackup", now.addingTimeInterval(-3_600)))
            try Fix1102Fixtures.touch(newer, modified: now.addingTimeInterval(-10_800))
            // Newest of all, but written during a first download.
            try Fix1102Fixtures.touch(mac.appendingPathComponent(Self.name("Partial-AutoBackup", now)), modified: now)

            #expect(Self.path(AutoBackupFolders.mostRecentBackup(in: [auto])) == Self.path(newer))

            // The iPad's newer one, still in iCloud: found by its real name.
            let padName = Self.name("ScheduledBackup", now.addingTimeInterval(-1_800))
            let placeholder = pad.appendingPathComponent(".\(padName).icloud")
            try Fix1102Fixtures.touch(placeholder, modified: now.addingTimeInterval(-86_400))
            let newest = try #require(AutoBackupFolders.mostRecentBackup(in: [auto]))
            #expect(newest.lastPathComponent == padName)
            #expect(UbiquitousFile.needsDownload(newest))
        }
    }

    @Test("Partial backups are trimmed among themselves and never push out complete ones")
    func partialBackupsTrimmedApart() async throws {
        try await Fix1102Fixtures.withFolder { auto in
            let device = auto.appendingPathComponent("Mac-AAAA0000", isDirectory: true)
            let start = Date().addingTimeInterval(-100 * 3_600)
            var complete: [String] = []
            var partial: [String] = []
            for index in 0..<3 {
                let made = start.addingTimeInterval(Double(index) * 3_600)
                complete.append(Self.name("AutoBackup", made))
                try Fix1102Fixtures.touch(device.appendingPathComponent(complete[index]), modified: made)
            }
            for index in 0..<3 {
                // Newer than every complete one.
                let made = start.addingTimeInterval(Double(10 + index) * 3_600)
                partial.append(Self.name("Partial-AutoBackup", made))
                try Fix1102Fixtures.touch(device.appendingPathComponent(partial[index]), modified: made)
            }
            let manual = Self.name("Partial-ManualBackup", start)
            try Fix1102Fixtures.touch(device.appendingPathComponent(manual), modified: start)

            AutoBackupFolders.trimAfterBackup(autoFolder: auto, deviceFolder: device, keeping: 2) {
                try FileManager.default.removeItem(at: $0)
            }
            let left = Set(try FileManager.default.contentsOfDirectory(atPath: device.path))
            #expect(left == Set(complete.suffix(2) + partial.suffix(2) + [manual]))
        }
    }
}

// MARK: - The manager: partial names, and how this device's backups have gone (#12, #14)

@Suite("Automatic backup outcomes (Fix1102 #12 #14)", .serialized)
@MainActor
struct AutoBackupOutcomesFix1102Tests {

    private static let markKey = "Fix1102.keychainMark"

    private static func deviceDefaults() throws -> (UserDefaults, String) {
        let suite = "Fix1102-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private static func manager(
        _ defaults: UserDefaults, _ suite: String, autoFolder: URL, firstDownloadPending: Bool
    ) -> AutoBackupManager {
        let key = markKey
        return AutoBackupManager(
            coordinator: BackupCoordinator(
                backupService: BackupService(),
                transactionManager: BackupTransactionManager(),
                appRouter: AppRouter()
            ),
            deviceDefaults: defaults,
            deviceMark: AutoBackupFolders.DeviceMark(
                read: { UserDefaults(suiteName: suite)?.string(forKey: key) },
                write: { UserDefaults(suiteName: suite)?.set($0, forKey: key) }
            ),
            autoFolder: autoFolder,
            changeTracker: BackupChangeTracker(defaults: defaults),
            firstDownloadPending: { firstDownloadPending }
        )
    }

    /// Runs `body` with the automatic-backup switch on, as it is by default.
    private static func withAutomaticBackupsOn(_ body: () async throws -> Void) async rethrows {
        let key = UserDefaultsKeys.autoBackupEnabled
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try await body()
    }

    private static let keys = Fix1102KeyBox([Fix1102KeyBox.legacyKey()])

    @Test("A backup during a first download is named Partial-, says so, and isn't this device's last backup")
    func partialBackup() async throws {
        let context = try Fix1102Fixtures.notebookWithOneStudent()
        let (defaults, suite) = try Self.deviceDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        try await Fix1102Fixtures.withFolder { auto in
            try await BackupEncryptionKeyStore.$items.withValue(Self.keys.items) { () async throws in
                let during = Self.manager(defaults, suite, autoFolder: auto, firstDownloadPending: true)
                let partial = await during.performManualBackup(viewContext: context)
                guard case .success(_, let partialURL) = partial else {
                    Issue.record("the backup wasn't written: \(partial)")
                    return
                }
                #expect(partialURL.lastPathComponent.hasPrefix("Partial-ManualBackup-"))
                #expect(try MCPNotebookTools.backupReceipt(partial).contains(AutoBackupManager.firstDownloadWarning))
                #expect(during.lastBackupOnThisDevice == nil)
                #expect(AutoBackupFolders.mostRecentBackup(in: [auto]) == nil)

                let after = Self.manager(defaults, suite, autoFolder: auto, firstDownloadPending: false)
                let complete = await after.performManualBackup(viewContext: context)
                guard case .success(_, let completeURL) = complete else {
                    Issue.record("the backup wasn't written: \(complete)")
                    return
                }
                #expect(completeURL.lastPathComponent.hasPrefix("ManualBackup-"))
                #expect(try !MCPNotebookTools.backupReceipt(complete).contains(AutoBackupManager.firstDownloadWarning))
                #expect(after.lastBackupOnThisDevice != nil)
                #expect(AutoBackupFolders.mostRecentBackup(in: [auto])?.lastPathComponent
                    == completeURL.lastPathComponent)
            }
        }
    }

    @Test("Failing automatic backups are remembered from the first failure until one works; manual ones aren't")
    func failingAutomaticBackups() async throws {
        let context = try Fix1102Fixtures.notebookWithOneStudent()
        let (defaults, suite) = try Self.deviceDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        try await Fix1102Fixtures.withFolder { root in
            // `Auto/` can't be made: a file is in the way.
            let blocker = root.appendingPathComponent("Blocker")
            try Data("x".utf8).write(to: blocker)
            let broken = blocker.appendingPathComponent("Auto", isDirectory: true)
            try await Self.withAutomaticBackupsOn {
                try await BackupEncryptionKeyStore.$items.withValue(Self.keys.items) {
                    let failing = Self.manager(defaults, suite, autoFolder: broken, firstDownloadPending: false)
                    _ = await failing.performManualBackup(viewContext: context)
                    #expect(
                        failing.automaticBackupFailingSince == nil, "a manual backup's failure is shown where it ran"
                    )

                    await failing.performBackupOnQuit(viewContext: context)
                    guard case .failure? = failing.lastBackupResult else {
                        Issue.record("the backup didn't fail: \(String(describing: failing.lastBackupResult))")
                        return
                    }
                    let since = try #require(failing.automaticBackupFailingSince)
                    await failing.performBackupOnQuit(viewContext: context)
                    #expect(failing.automaticBackupFailingSince == since, "from the first failure")
                    #expect(defaults.object(forKey: AutoBackupManager.inFlightKey) == nil)

                    let working = Self.manager(
                        defaults, suite, autoFolder: root.appendingPathComponent("Auto"), firstDownloadPending: false
                    )
                    #expect(working.automaticBackupFailingSince == since)
                    await working.performBackupOnQuit(viewContext: context)
                    #expect(working.automaticBackupFailingSince == nil)
                    #expect(working.lastBackupOnThisDevice != nil)
                }
            }
        }
    }

    @Test("An automatic backup cut short is a failure at the next launch")
    func cutShortBackup() throws {
        let (defaults, suite) = try Self.deviceDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let started = Date(timeIntervalSinceReferenceDate: 815_299_200)
        defaults.set(started.timeIntervalSinceReferenceDate, forKey: AutoBackupManager.inFlightKey)

        let manager = Self.manager(
            defaults, suite, autoFolder: FileManager.default.temporaryDirectory, firstDownloadPending: false
        )
        #expect(manager.automaticBackupFailingSince == started)
        #expect(defaults.object(forKey: AutoBackupManager.inFlightKey) == nil)
    }

    @Test("A run the system ended, or a key still on its way, isn't a failure")
    func whatCountsAsFailure() {
        struct DiskFull: Error {}
        #expect(AutoBackupManager.countsAsFailure(DiskFull()))
        #expect(!AutoBackupManager.countsAsFailure(CancellationError()))
        #expect(!AutoBackupManager.countsAsFailure(BackupEncryptionKeyStore.KeyStoreError.keyNotHereYet))
        #expect(AutoBackupManager.countsAsFailure(BackupEncryptionKeyStore.KeyStoreError.keyUnavailableForRestore))
    }
}

// MARK: - The Overview's backup row (#12)

@Suite("Failing automatic backups on the Overview (Fix1102 #12)")
struct SettingsAttentionFailingBackupsFix1102Tests {

    private let calendar = AppCalendar.shared
    private var noon: Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSinceReferenceDate: 800_000_000))
            ?? Date(timeIntervalSinceReferenceDate: 800_000_000)
    }

    @Test("This device's failing automatic backups show, however recent another backup is")
    func failingRow() {
        let now = noon
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        var inputs = SettingsAttentionInputs(lastBackup: yesterday, syncHealth: .healthy)
        inputs.deviceKind = "iPad"
        #expect(SettingsAttention.items(for: inputs, now: now).isEmpty)

        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        inputs.automaticBackupFailingSince = threeDaysAgo
        let items = SettingsAttention.items(for: inputs, now: now)
        #expect(items.map(\.id) == ["backup"])
        let since = threeDaysAgo.formatted(date: .long, time: .omitted)
        #expect(items.first?.title == "This iPad's automatic backups haven't worked since \(since)")

        inputs.automaticBackupFailingSince = now.addingTimeInterval(-3_600)
        #expect(SettingsAttention.items(for: inputs, now: now).first?.title
            == "This iPad's last automatic backup didn't work")
    }
}

// MARK: - The size estimate (#21)

@Suite("Backup size estimate (Fix1102 #21)")
@MainActor
struct BackupSizeEstimateFix1102Tests {

    @Test("The estimate counts every backed-up type")
    func countsEveryType() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: context)
        let counts = BackupSizeEstimator.countEntities(viewContext: context)
        #expect(Set(counts.keys) == Set(BackupEntityTable.names))
        let missing = BackupEntityTable.names.filter { (counts[$0] ?? 0) == 0 }
        #expect(missing.isEmpty, "not counted: \(missing)")
        #expect(BackupSizeEstimator.estimateBackupSize(viewContext: context, includesPhotos: false)
            == BackupSizeEstimator.estimateFromCounts(counts))
    }
}
