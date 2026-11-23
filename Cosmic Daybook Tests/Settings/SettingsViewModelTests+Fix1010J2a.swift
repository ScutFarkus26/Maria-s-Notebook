import CoreData
import Foundation
import Observation
import Synchronization
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #82 and #90's restore sheet: a backup, preview or
// restore that failed part-way left the Backups card's progress bar up (and
// its buttons off) until a relaunch; a restore stamped "Last backup just now",
// hiding the "backup is N days old" warning; and Restore Now left the preview
// sheet up, with no progress, over the alert a failure raised.
@Suite("Backups card and restore (Fix1010 J2a)", .serialized)
@MainActor
struct SettingsViewModelFix1010J2aTests {
    private static let lastBackupKey = "LastBackupTimeInterval"

    private struct Harness {
        let model: SettingsViewModel
        let context: NSManagedObjectContext
        let directory: URL
    }

    /// A Backups card over an empty notebook, and a folder for backup files.
    private static func harness() throws -> Harness {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsFix1010J2a-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = SettingsViewModel(dependencies: AppDependencies(coreDataStack: stack))
        return Harness(model: model, context: stack.viewContext, directory: directory)
    }

    /// A backup of a notebook holding one child, carrying `preferences`.
    private static func backup(
        in directory: URL, preferences: [String: PreferenceValueDTO] = [:]
    ) async throws -> URL {
        let source = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: source, firstName: "Ada", lastName: "Lovelace")
        #expect(CoreDataTestHelpers.save(source))
        let url = directory.appendingPathComponent("Source").appendingPathExtension(BackupFile.fileExtension)
        let recorder = BackupPipelineRecorder(preferences: PreferencesDTO(values: preferences))
        _ = try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await BackupWriter.write(viewContext: source, to: url)
        }
        return url
    }

    private static func students(in context: NSManagedObjectContext) -> Int {
        context.safeFetch(CDFetchRequest(CDStudent.self)).count
    }

    /// Runs `body` with this device's last-backup time set to `date`, and
    /// puts the real one back after.
    private static func withLastBackup(_ date: Date?, _ body: () async throws -> Void) async rethrows {
        let saved = UserDefaults.standard.object(forKey: lastBackupKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: lastBackupKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastBackupKey)
            }
        }
        if let date {
            UserDefaults.standard.set(date.timeIntervalSinceReferenceDate, forKey: lastBackupKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastBackupKey)
        }
        try await body()
    }

    /// Previews `url` and requires the preview sheet's contents.
    private static func preview(_ url: URL, with harness: Harness) async throws {
        await harness.model.previewImportedURL(viewContext: harness.context, url: url)
        try #require(
            harness.model.restorePreviewData != nil,
            "no preview: \(harness.model.importError ?? "no message")"
        )
    }

    // MARK: - The card after a failure

    @Test("A preview that fails part-way says so and frees the card")
    func failedPreviewFreesTheCard() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        // Looks like a backup (the encrypted archive's first four bytes), isn't one.
        let broken = harness.directory.appendingPathComponent("Broken").appendingPathExtension(BackupFile.fileExtension)
        try (Data("AEA1".utf8) + Data((0..<512).map { UInt8(truncatingIfNeeded: $0 &* 31) })).write(to: broken)

        await harness.model.previewImportedURL(viewContext: harness.context, url: broken)

        #expect(harness.model.importError != nil)
        #expect(harness.model.restorePreviewData == nil)
        #expect(harness.model.importProgress == 0, "the progress bar would stay up and the buttons off")
        #expect(harness.model.importMessage.isEmpty)
    }

    @Test("A restore that fails part-way says so and frees the card")
    func failedRestoreFreesTheCard() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let url = try await Self.backup(in: harness.directory)
        try await Self.preview(url, with: harness)

        struct Stop: Error {}
        let failing = BackupPipelineRecorder(failure: { $0 == "import Student" ? Stop() : nil })
        harness.model.confirmRestore()
        await BackupPipelineRecorder.$current.withValue(failing) {
            await harness.model.restorePreviewDismissed(viewContext: harness.context)
        }

        #expect(harness.model.importError != nil)
        #expect(harness.model.importProgress == 0, "the progress bar would stay up and the buttons off")
        #expect(Self.students(in: harness.context) == 0)
    }

    // MARK: - The last backup time

    @Test("A restore isn't a backup: the last backup time stays as it was")
    func restoreDoesNotStampTheBackupTime() async throws {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86_400)
        try await Self.withLastBackup(threeDaysAgo) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            let url = try await Self.backup(in: harness.directory)
            try await Self.preview(url, with: harness)

            harness.model.confirmRestore()
            await harness.model.restorePreviewDismissed(viewContext: harness.context)

            #expect(harness.model.importError == nil)
            #expect(Self.students(in: harness.context) == 1)
            #expect(harness.model.lastBackupDate?.timeIntervalSinceReferenceDate
                == threeDaysAgo.timeIntervalSinceReferenceDate)
        }
    }

    @Test("An older backup's settings don't turn the last backup time back; a fresh device takes the backup's")
    func restoreKeepsTheLaterBackupTime() async throws {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86_400)
        let tenDaysAgo = Date().addingTimeInterval(-10 * 86_400)
        let carried = [Self.lastBackupKey: PreferenceValueDTO.double(tenDaysAgo.timeIntervalSinceReferenceDate)]

        try await Self.withLastBackup(threeDaysAgo) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            try await Self.preview(try await Self.backup(in: harness.directory, preferences: carried), with: harness)
            harness.model.confirmRestore()
            await harness.model.restorePreviewDismissed(viewContext: harness.context)
            #expect(harness.model.lastBackupDate?.timeIntervalSinceReferenceDate
                == threeDaysAgo.timeIntervalSinceReferenceDate)
        }

        try await Self.withLastBackup(nil) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            try await Self.preview(try await Self.backup(in: harness.directory, preferences: carried), with: harness)
            harness.model.confirmRestore()
            await harness.model.restorePreviewDismissed(viewContext: harness.context)
            #expect(harness.model.lastBackupDate?.timeIntervalSinceReferenceDate
                == tenDaysAgo.timeIntervalSinceReferenceDate)
        }
    }

    // MARK: - The preview sheet

    @Test("Restore Now closes the preview first; the restore runs once it has gone, and the card is free after")
    func restoreNowClosesThePreviewFirst() async throws {
        try await Self.withLastBackup(nil) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            try await Self.preview(try await Self.backup(in: harness.directory), with: harness)

            harness.model.confirmRestore()
            #expect(harness.model.restorePreviewData == nil, "the sheet closes on Restore Now")
            #expect(Self.students(in: harness.context) == 0, "nothing restored while the sheet is still going")

            await harness.model.restorePreviewDismissed(viewContext: harness.context)
            #expect(Self.students(in: harness.context) == 1)
            #expect(harness.model.importError == nil)
            #expect(harness.model.importProgress == 0)
            #expect(harness.model.operationSummary != nil)
        }
    }

    @Test("Closing the preview any other way restores nothing, then or later")
    func dismissingWithoutRestoreNowRestoresNothing() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        try await Self.preview(try await Self.backup(in: harness.directory), with: harness)

        harness.model.restorePreviewData = nil  // Cancel, or a swipe down
        await harness.model.restorePreviewDismissed(viewContext: harness.context)
        await harness.model.performImportConfirmed(viewContext: harness.context)

        #expect(Self.students(in: harness.context) == 0)
        #expect(harness.model.operationSummary == nil)
    }
}

// MARK: - The last backup time, told to every reader

/// Set once a tracked read is told its value is about to change.
nonisolated private final class ReaderTold: Sendable {
    private let flag = Mutex(false)
    var value: Bool { flag.withLock { $0 } }
    func set() { flag.withLock { $0 = true } }
}

// State layer fixes 2026-11, B6: the Backups card's date was read straight
// from UserDefaults, which Observation can't see, so a backup stamped by
// another Backups card, by the Overview's Back Up Now, or carried in by a
// restore told no reader. One shared `LastBackupStamp` now tells them all.
extension SettingsViewModelFix1010J2aTests {

    /// Whether a view reading `model.lastBackupDate` is told during `change`.
    private static func readerIsTold(
        of model: SettingsViewModel, during change: () async throws -> Void
    ) async rethrows -> Bool {
        let told = ReaderTold()
        _ = withObservationTracking { model.lastBackupDate } onChange: { told.set() }
        try await change()
        return told.value
    }

    @Test("A backup stamped on one Backups card tells a reader of another, and the status reads the same time")
    func stampOnAnotherCardTellsTheReader() async throws {
        try await Self.withLastBackup(Date().addingTimeInterval(-3 * 86_400)) {
            let reader = try Self.harness()
            let writer = try Self.harness()
            defer {
                try? FileManager.default.removeItem(at: reader.directory)
                try? FileManager.default.removeItem(at: writer.directory)
            }
            let before = Date()

            let told = await Self.readerIsTold(of: reader.model) { writer.model.setLastBackupNow() }

            #expect(told, "the card would keep showing the old time until something else redrew it")
            let shown = try #require(reader.model.lastBackupDate)
            #expect(shown.timeIntervalSinceReferenceDate >= before.timeIntervalSinceReferenceDate)
            #expect(BackupVerification.getBackupStatus().lastBackupDate == shown)
        }
    }

    @Test("The Overview's Back Up Now tells a reader of the Backups card")
    func overviewBackUpNowTellsTheCard() async throws {
        try await Self.withLastBackup(nil) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            CoreDataTestHelpers.seedStudent(in: harness.context, firstName: "Ada", lastName: "Lovelace")
            #expect(CoreDataTestHelpers.save(harness.context))
            // A backup manager that writes into the scratch folder, with this
            // test's own device settings and folder mark.
            let suite = "SettingsFix1010J2a-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let dependencies = harness.model.dependencies
            dependencies._autoBackupManager = AutoBackupManager(
                coordinator: dependencies.backupCoordinator,
                deviceDefaults: defaults,
                deviceMark: AutoBackupFolders.DeviceMark(
                    read: { UserDefaults(suiteName: suite)?.string(forKey: "mark") },
                    write: { UserDefaults(suiteName: suite)?.set($0, forKey: "mark") }
                ),
                autoFolder: harness.directory.appendingPathComponent("Auto", isDirectory: true),
                changeTracker: BackupChangeTracker(defaults: defaults),
                firstDownloadPending: { false }
            )
            let overview = SettingsDashboardViewModel(dependencies: dependencies)
            let keys = Fix1102KeyBox([Fix1102KeyBox.legacyKey()])

            let told = await BackupEncryptionKeyStore.$items.withValue(keys.items) {
                await Self.readerIsTold(of: harness.model) {
                    await overview.backUpNow(viewContext: harness.context)
                }
            }

            #expect(overview.backupRun == .succeeded(partial: false))
            #expect(told, "the Backups card would keep showing the old time")
            #expect(harness.model.lastBackupDate != nil)
        }
    }

    @Test("A restore that brings its own last backup time tells the card's reader")
    func restoreTellsTheCard() async throws {
        let tenDaysAgo = Date().addingTimeInterval(-10 * 86_400)
        let carried = [Self.lastBackupKey: PreferenceValueDTO.double(tenDaysAgo.timeIntervalSinceReferenceDate)]
        try await Self.withLastBackup(nil) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            try await Self.preview(try await Self.backup(in: harness.directory, preferences: carried), with: harness)
            harness.model.confirmRestore()

            let told = await Self.readerIsTold(of: harness.model) {
                await harness.model.restorePreviewDismissed(viewContext: harness.context)
            }

            #expect(harness.model.importError == nil)
            #expect(told, "the restore's settings set the time straight into the defaults")
            #expect(harness.model.lastBackupDate?.timeIntervalSinceReferenceDate
                == tenDaysAgo.timeIntervalSinceReferenceDate)
        }
    }
}
