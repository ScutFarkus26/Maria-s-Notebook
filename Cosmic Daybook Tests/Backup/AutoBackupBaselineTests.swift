import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// 2026-10-05 sync hunt: an automatic backup's "nothing changed since" baseline
// is what the stores held before its rows were collected, so a change saved
// while the file is being written still counts for the next one; and automatic
// backups wait while the first download from iCloud is under way.
@Suite("Automatic backup baseline")
@MainActor
struct AutoBackupBaselineTests {

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AutoBackupBaselineTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    /// A notebook on disk, so its store keeps persistent history.
    private func makeStack() throws -> (CoreDataStack, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoBackupBaseline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stack = try CoreDataStack(
            enableCloudKit: false, localStoreURL: directory.appendingPathComponent("notebook.sqlite")
        )
        return (stack, directory)
    }

    @Test("A change saved while the backup is written is still a change for the next one")
    func changeDuringTheWriteIsNotLost() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (stack, directory) = try makeStack()
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = stack.viewContext
        let tracker = BackupChangeTracker(defaults: defaults)

        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        #expect(CoreDataTestHelpers.save(context))

        // The backup takes its baseline, then an assistant's mark lands mid-write.
        let baseline = tracker.currentHistoryToken(context: context)
        #expect(baseline != nil)
        _ = CoreDataTestHelpers.seedAttendance(in: context)
        #expect(CoreDataTestHelpers.save(context))
        tracker.recordBackupPoint(baseline)

        #expect(tracker.hasChangesSinceLastBackup(in: context))

        // With nothing saved after the baseline, the next backup is skipped.
        tracker.recordBackupPoint(tracker.currentHistoryToken(context: context))
        #expect(!tracker.hasChangesSinceLastBackup(in: context))
    }

    // Bug hunt 2026-11-02 #14: the wait lasted a day at most, and then a
    // half-downloaded notebook's backups took the usual names and trimmed the
    // whole ones. Now they are written, under a name that marks them.
    @Test("A backup made during a first download is named Partial-; one made after isn't")
    func backupsDuringTheFirstDownloadAreMarked() {
        for prefix in ["AutoBackup", "ScheduledBackup", "ManualBackup"] {
            #expect(AutoBackupManager.fileNamePrefix(prefix, firstDownloadPending: true) == "Partial-" + prefix)
            #expect(AutoBackupManager.fileNamePrefix(prefix, firstDownloadPending: false) == prefix)
        }
        #expect(AutoBackupFolders.isPartial("Partial-AutoBackup-2026-11-02T08:00:00.000Z.mtbbackup"))
        #expect(!AutoBackupFolders.isPartial("AutoBackup-2026-11-02T08:00:00.000Z.mtbbackup"))
    }

    @Test("Only the notebook's two-store layout gets the history processor")
    func singleStoreFallbackHasNoHistoryProcessor() {
        // With iCloud, and the cached two-store copy without it.
        #expect(CoreDataStack.makesHistoryProcessor(
            opensAppStores: true, enableCloudKit: true, preserveSplitStoreLayout: false
        ))
        #expect(CoreDataStack.makesHistoryProcessor(
            opensAppStores: true, enableCloudKit: false, preserveSplitStoreLayout: true
        ))
        // The no-iCloud single-store fallback, and stores that aren't the notebook's.
        #expect(!CoreDataStack.makesHistoryProcessor(
            opensAppStores: true, enableCloudKit: false, preserveSplitStoreLayout: false
        ))
        #expect(!CoreDataStack.makesHistoryProcessor(
            opensAppStores: false, enableCloudKit: true, preserveSplitStoreLayout: false
        ))
    }
}
