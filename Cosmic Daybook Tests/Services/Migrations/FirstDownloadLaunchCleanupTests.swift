import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Logic-break sweep 2026-09-29, Group A item 1. The launch cleanups that judge
// a row by what else is in the store (orphaned students on assignments and
// work rows, check-ins whose work is missing) ran during the first download
// after Reset Local Cache or on a new device. Rows that hadn't arrived yet
// read as gone, so they cleared student links and deleted check-ins, and
// those changes went back up to iCloud. While `FirstDownloadGate` is armed
// they now leave everything alone.

@Suite("Launch cleanups wait for the first download")
@MainActor
struct FirstDownloadLaunchCleanupTests {
    private typealias Fixture = LaunchRepairFixture

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "FirstDownloadLaunchCleanupTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    @Test("While the first download is pending the orphan passes change no row")
    func orphanPassesSkippedWhilePending() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try Fixture.seed(stack.viewContext)
        let seeded = Fixture.snapshot(of: stack.viewContext)

        let outcome = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: true
        ) { _ in [:] }

        let result = Fixture.snapshot(of: stack.viewContext)
        #expect(outcome.workRowsCleaned == 0)
        #expect(result.workStudents == seeded.workStudents)
        #expect(result.participantStudents == seeded.participantStudents)
        #expect(result.assignmentStudents == seeded.assignmentStudents)
        // The scheduled-day mirror doesn't judge by other rows, so it still runs.
        #expect(result.assignmentDays != seeded.assignmentDays)
    }

    @Test("Once the download is done the same pass cleans as before")
    func orphanPassesRunOnceOpen() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try Fixture.seed(stack.viewContext)

        let outcome = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false
        ) { _ in [:] }

        #expect(outcome.workRowsCleaned == 5)
    }

    @Test("The check-in repair relinks but keeps orphans while the download is pending, and doesn't count the run")
    func checkInRepairKeepsOrphansWhilePending() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        CoreDataTestHelpers.save(context)
        let linked = CDWorkCheckIn(context: context)
        linked.workID = try #require(work.id?.uuidString)
        linked.date = Date()
        let orphan = CDWorkCheckIn(context: context)
        orphan.workID = UUID().uuidString
        orphan.date = Date()
        CoreDataTestHelpers.save(context)

        // A device that has run the repair before (the flag survived a reset
        // on older builds) still keeps the orphan while the download runs.
        defaults.set(true, forKey: UserDefaultsKeys.checkInLinkRepairHasRun)
        let pending = DataMigrations.repairWorkCheckInLinks(
            using: context, firstDownloadPending: true, defaults: defaults
        )
        #expect(pending == .init(relinked: 1, orphansDeleted: 0, orphansKept: 1))
        #expect(linked.work === work)
        #expect(!orphan.isDeleted)

        // A first run during the download doesn't count as the first run.
        defaults.removeObject(forKey: UserDefaultsKeys.checkInLinkRepairHasRun)
        _ = DataMigrations.repairWorkCheckInLinks(using: context, firstDownloadPending: true, defaults: defaults)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.checkInLinkRepairHasRun))

        // After the download: the lenient first run, then orphans go.
        let first = DataMigrations.repairWorkCheckInLinks(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(first.orphansKept == 1)
        #expect(defaults.bool(forKey: UserDefaultsKeys.checkInLinkRepairHasRun))
        let second = DataMigrations.repairWorkCheckInLinks(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(second.orphansDeleted == 1)
    }

    // A2: the local fallback after a CloudKit failure opened the gate for
    // good, so a download interrupted that way was treated as complete.
    @Test("Only turning sync off opens the gate; a launch that fell back from CloudKit leaves it armed")
    func gateOpensOnlyWhenSyncIsOff() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CoreDataStack.updateFirstDownloadGate(enableCloudKit: true, privateStoreExists: false, defaults: defaults)
        #expect(FirstDownloadGate.isPending(defaults: defaults))

        // CloudKit failed this launch; the guide still wants sync.
        CoreDataStack.updateFirstDownloadGate(enableCloudKit: false, privateStoreExists: true, defaults: defaults)
        #expect(FirstDownloadGate.isPending(defaults: defaults))

        // Back on CloudKit with the partial store: still held.
        CoreDataStack.updateFirstDownloadGate(enableCloudKit: true, privateStoreExists: true, defaults: defaults)
        #expect(FirstDownloadGate.isPending(defaults: defaults))

        // The guide turned sync off: nothing will download, so nothing waits.
        defaults.set(false, forKey: UserDefaultsKeys.enableCloudKitSync)
        CoreDataStack.updateFirstDownloadGate(enableCloudKit: false, privateStoreExists: true, defaults: defaults)
        #expect(!FirstDownloadGate.isPending(defaults: defaults))
    }

    @Test("Reset Local Cache clears the check-in repair's first-run flag")
    func resetClearsCheckInRepairFlag() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: UserDefaultsKeys.checkInLinkRepairHasRun)
        defaults.set(true, forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)

        CoreDataStack.clearLocalCacheResetFlags(in: defaults)

        #expect(!defaults.bool(forKey: UserDefaultsKeys.checkInLinkRepairHasRun))
        #expect(!defaults.bool(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch))
    }
}
