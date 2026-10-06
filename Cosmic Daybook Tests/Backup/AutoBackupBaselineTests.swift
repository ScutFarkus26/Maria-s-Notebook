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

    @Test("Automatic backups wait during a first download; manual ones never do")
    func automaticBackupsWaitForTheFirstDownload() {
        for trigger in [AutoBackupManager.BackupTrigger.appQuit, .scheduled, .background] {
            #expect(AutoBackupManager.waitsForFirstDownload(trigger, firstDownloadPending: true))
            #expect(!AutoBackupManager.waitsForFirstDownload(trigger, firstDownloadPending: false))
        }
        #expect(!AutoBackupManager.waitsForFirstDownload(.manual, firstDownloadPending: true))
    }

    @Test("A first download that never finishes holds backups back for a day at most")
    func firstDownloadWaitHasALimit() throws {
        let defaults = try #require(UserDefaults(suiteName: "AutoBackupBaselineTests.armedAt"))
        defer { defaults.removePersistentDomain(forName: "AutoBackupBaselineTests.armedAt") }
        let now = Date()
        // Armed by an older build: no time recorded, so nothing is held back.
        #expect(!FirstDownloadGate.armedRecently(within: 86_400, now: now, defaults: defaults))
        FirstDownloadGate.arm(defaults: defaults)
        #expect(FirstDownloadGate.armedRecently(within: 86_400, now: now, defaults: defaults))
        let nextDay = now.addingTimeInterval(90_000)
        #expect(!FirstDownloadGate.armedRecently(within: 86_400, now: nextDay, defaults: defaults))
        FirstDownloadGate.open(defaults: defaults)
        #expect(defaults.object(forKey: FirstDownloadGate.armedAtKey) == nil)
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
