import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Hunt of 2026-10-05, #17: every copy of the app ran the launch's store surgery
// (the reset, migration backup and restore, the stale-key repair, the orphan
// cleanup, the schema stamp) whether or not another copy had the files open.
// `flock` locks belong to an open file, so two `StoreProcessLock`s on one
// folder exclude each other exactly as two running copies of the app would.

@Suite("Store lock: one copy does store surgery")
@MainActor
struct StoreProcessLockTests {

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "StoreProcessLockTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    // MARK: - The lock

    @Test("The first copy has the stores to itself; a second opens them shared and isn't primary")
    func firstCopyIsPrimary() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let first = StoreProcessLock(directory: fixture.directory)
        let second = StoreProcessLock(directory: fixture.directory)
        defer { first.close(); second.close() }

        #expect(first.tryExclusive())
        first.releaseExclusive()
        #expect(first.isPrimary)

        #expect(!second.tryExclusive(), "the first copy is still running")
        #expect(second.holdShared(timeout: .milliseconds(100)))
        #expect(!second.isPrimary)
        #expect(!second.holdsExclusive)
    }

    @Test("Surgery waits until every other copy has closed")
    func surgeryNeedsEveryOtherCopyGone() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let first = StoreProcessLock(directory: fixture.directory)
        let second = StoreProcessLock(directory: fixture.directory)
        defer { second.close() }

        #expect(first.tryExclusive())
        first.releaseExclusive()
        #expect(!second.tryExclusive())
        // A refused try keeps the second copy's shared hold, so the first
        // can't take the stores from under it either.
        #expect(!first.tryExclusive())

        first.close()
        #expect(second.tryExclusive(), "the other copy quit")
        #expect(!second.isPrimary, "primary is decided at launch")
    }

    @Test("A second copy becomes the primary once the first has quit, and only then")
    func secondCopyTakesOverWhenAlone() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let first = StoreProcessLock(directory: fixture.directory)
        let second = StoreProcessLock(directory: fixture.directory)
        defer { second.close() }

        #expect(first.tryExclusive())
        first.releaseExclusive()
        #expect(!second.tryExclusive())
        #expect(second.isSecondary)
        #expect(!second.promoteIfAlone(), "the first copy is still open")
        #expect(first.isPrimary)

        first.close()
        #expect(second.promoteIfAlone())
        #expect(second.isPrimary && !second.isSecondary)
        #expect(!second.holdsExclusive, "promotion leaves the shared hold, not surgery")
    }

    @Test("A copy that never opened stores is never promoted")
    func noStoresNoPromotion() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let lock = StoreProcessLock(directory: fixture.directory)
        defer { lock.close() }
        #expect(!lock.promoteIfAlone())
        #expect(!lock.isPrimary)
    }

    @Test("A copy arriving mid-surgery waits for it instead of opening the files halfway")
    func newcomerWaitsOutSurgery() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let first = StoreProcessLock(directory: fixture.directory)
        let second = StoreProcessLock(directory: fixture.directory)
        defer { first.close(); second.close() }

        #expect(first.tryExclusive())
        #expect(!second.tryExclusive())
        #expect(!second.holdShared(timeout: .milliseconds(100)), "the first copy is migrating")

        first.releaseExclusive()
        #expect(second.holdShared(timeout: .milliseconds(100)))
    }

    @Test("Asking again while holding the stores counts; giving them back keeps the shared hold")
    func reentrantAndBackToShared() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let first = StoreProcessLock(directory: fixture.directory)
        let second = StoreProcessLock(directory: fixture.directory)
        defer { first.close(); second.close() }

        #expect(first.tryExclusive())
        #expect(first.tryExclusive())
        #expect(first.holdsExclusive)
        first.releaseExclusive()
        #expect(!first.holdsExclusive)
        #expect(!second.tryExclusive(), "the first copy still holds the stores shared")
    }

    // MARK: - Launch

    @Test("A launch beside a running copy opens without surgery; beside one mid-surgery it refuses")
    func launchClaim() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let running = StoreProcessLock(directory: fixture.directory)
        let launching = StoreProcessLock(directory: fixture.directory)
        let third = StoreProcessLock(directory: fixture.directory)
        defer { running.close(); launching.close(); third.close() }

        #expect(try CoreDataStack.claimStoresForLaunch(lock: running))
        running.releaseExclusive()
        #expect(try !CoreDataStack.claimStoresForLaunch(lock: launching, wait: .milliseconds(100)))

        launching.close()
        running.close()
        #expect(try CoreDataStack.claimStoresForLaunch(lock: launching))
        #expect(throws: CoreDataStackError.self) {
            try CoreDataStack.claimStoresForLaunch(lock: third, wait: .milliseconds(100))
        }
    }

    @Test("An armed Re-download waits while another copy has the stores, and the stores aren't opened")
    func armedResetWaitsForOtherCopy() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)

        #expect(throws: CoreDataStackError.self) {
            try CoreDataStack.prepareOnDiskStores(enableCloudKit: true, surgeryAllowed: false, defaults: defaults)
        }
        #expect(defaults.bool(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch), "still armed for the next launch")
    }

    @Test("With iCloud sync off an armed Re-download is dropped, never carried out")
    func armedResetDroppedWhenSyncIsOff() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: UserDefaultsKeys.enableCloudKitSync)
        defaults.set(true, forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
        defaults.set(true, forKey: UserDefaultsKeys.checkInLinkRepairHasRun)

        try CoreDataStack.prepareOnDiskStores(enableCloudKit: false, surgeryAllowed: true, defaults: defaults)

        #expect(!defaults.bool(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch))
        #expect(defaults.bool(forKey: UserDefaultsKeys.checkInLinkRepairHasRun), "no reset ran, so its flags stay")
    }

    @Test("What a launch does about an armed Re-download")
    func resetDecision() {
        typealias Decision = CoreDataStack.LocalCacheResetDecision
        #expect(CoreDataStack.localCacheResetDecision(armed: false, syncPreferred: true, surgeryAllowed: true)
            == Decision.none)
        #expect(CoreDataStack.localCacheResetDecision(armed: true, syncPreferred: true, surgeryAllowed: true)
            == .reset)
        #expect(CoreDataStack.localCacheResetDecision(armed: true, syncPreferred: true, surgeryAllowed: false)
            == .waitForOtherCopy)
        #expect(CoreDataStack.localCacheResetDecision(armed: true, syncPreferred: false, surgeryAllowed: true)
            == .dropSyncOff)
    }

    @Test("The Re-download request belongs to one store environment")
    func resetKeyIsPerEnvironment() {
        let base = "AppCore.resetLocalCacheOnLaunch"
        #expect(UserDefaultsKeys.resetLocalCacheOnLaunch == CloudKitEnvironment.scoped(base))
        #expect(CloudKitEnvironment.production.scoped(base) != CloudKitEnvironment.development.scoped(base))
    }

    // MARK: - Surgery before load

    @Test("A store due to migrate isn't copied, edited or opened while another copy has it")
    func migrationWaitsForOtherCopy() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let url = try StoreFileFixture.makeStore(
            at: fixture.url("thing.sqlite"), model: StoreFileFixture.model(), rows: 2
        )
        let newer = StoreFileFixture.model(withNote: true)
        let container = StoreFileFixture.container(model: newer, url: url)

        #expect(throws: CoreDataStackError.self) {
            try CoreDataStack.prepareStoresForLoad(container: container, model: newer, surgeryAllowed: false)
        }
        let backup = url.deletingPathExtension().appendingPathExtension("premigration.sqlite")
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        #expect(CoreDataStack.storeNeedsMigration(storeURL: url, configuration: nil, model: newer), "left unmigrated")
        #expect(StoreFileFixture.stamp(at: url) == nil)
    }

    @Test("The routine repairs wait while another copy has the store, and run when it's alone")
    func routineRepairsSkipWhileShared() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let model = StoreFileFixture.model()
        let url = try StoreFileFixture.makeStore(at: fixture.url("thing.sqlite"), model: model, rows: 3)
        #expect(StoreFileFixture.execute(at: url, "UPDATE Z_PRIMARYKEY SET Z_MAX = 1 WHERE Z_NAME = 'Thing'"))
        let container = StoreFileFixture.container(model: model, url: url)

        try CoreDataStack.prepareStoresForLoad(container: container, model: model, surgeryAllowed: false)
        #expect(StoreFileFixture.thingCounter(at: url) == 1, "the stale-key repair waited")
        #expect(StoreFileFixture.stamp(at: url) == nil, "so did the stamp")

        try CoreDataStack.prepareStoresForLoad(container: container, model: model, surgeryAllowed: true)
        #expect(StoreFileFixture.thingCounter(at: url) == 3)
        #expect(StoreFileFixture.stamp(at: url) == CoreDataStack.currentSchemaVersion)
    }
}
