import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Hunt of 2026-10-05, #9 and #13. The "can't open notebook" screen deleted the
// store files with the app running, offered Re-download for a notebook a newer
// version had opened (and with iCloud sync off, when this copy is the only
// one), and a split store that failed to open sent the launch on to a separate,
// empty local store that looked like a fresh notebook.

@Suite("Database-error screen and fallback choices")
@MainActor
struct DatabaseErrorRecoveryTests {

    private let migrationFailure = NSError(domain: NSCocoaErrorDomain, code: NSMigrationError)

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "DatabaseErrorRecoveryTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    // MARK: - #9 The error screen

    @Test("Re-download isn't offered where it can't help: a newer version's notebook, another copy open, a damaged app")
    func redownloadHiddenWhereItCantHelp() {
        let hidden: [CoreDataStackError] = [
            .storeFromNewerBuild(storeName: "private.sqlite", storeVersion: 17, appVersion: 16),
            .storeInUseByAnotherCopy,
            .modelNotFound("CosmicDaybook")
        ]
        for error in hidden {
            #expect(DatabaseErrorCoordinator.redownloadOffer(for: error, syncPreferred: true) == .hidden)
        }
        let damaged = CoreDataStackError.storeSchemaIncoherent(storeName: "private.sqlite", detail: "x")
        #expect(DatabaseErrorCoordinator.redownloadOffer(for: damaged, syncPreferred: true) == .button)
        #expect(DatabaseErrorCoordinator.redownloadOffer(for: nil, syncPreferred: true) == .button)
    }

    @Test("With iCloud sync off the screen says there's nothing to download instead of offering it")
    func redownloadRefusedWithSyncOff() {
        let offer = DatabaseErrorCoordinator.redownloadOffer(
            for: CoreDataStackError.storeLoadFailed(migrationFailure), syncPreferred: false
        )
        #expect(offer == .unavailable(DatabaseErrorCoordinator.redownloadNeedsSyncMessage))
        let message = DatabaseErrorCoordinator.redownloadNeedsSyncMessage
        #expect(message.contains("iCloud sync is off"))
        for jargon in ["sqlite", "store", "CloudKit", "cache"] {
            #expect(!message.contains(jargon))
        }
    }

    @Test("Restore Backup isn't offered over a newer version's notebook or while another copy has it open")
    func restoreHiddenForNewerNotebook() {
        let newer = CoreDataStackError.storeFromNewerBuild(
            storeName: "private.sqlite", storeVersion: 17, appVersion: 16
        )
        #expect(!DatabaseErrorCoordinator.offersRestoreBackup(for: newer))
        #expect(!DatabaseErrorCoordinator.offersRestoreBackup(for: CoreDataStackError.storeInUseByAnotherCopy))
        let failed = CoreDataStackError.storeLoadFailed(migrationFailure)
        #expect(DatabaseErrorCoordinator.offersRestoreBackup(for: failed))
    }

    @Test("Re-download arms the next launch's reset and deletes nothing; with sync off it arms nothing")
    func redownloadArmsInsteadOfDeleting() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(DatabaseErrorCoordinator.shared.armRedownload(defaults: defaults))
        #expect(defaults.bool(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch))
        #expect(defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedSource) == "DatabaseErrorView")

        CoreDataStack.clearLocalCacheResetRequest(in: defaults)
        defaults.set(false, forKey: UserDefaultsKeys.enableCloudKitSync)
        #expect(!DatabaseErrorCoordinator.shared.armRedownload(defaults: defaults))
        #expect(!defaults.bool(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch))
    }

    @Test("The launch reset destroys a store with its journal through Core Data and leaves no files")
    func resetDestroysStoreAndCompanions() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let model = StoreFileFixture.model()
        let url = fixture.url("thing.sqlite")
        let missing = fixture.url("never-made.sqlite")
        // Left open while the rows are saved, so the WAL holds them.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        try StoreFileFixture.addRows(3, to: coordinator, model: model)
        try coordinator.remove(store)

        try CoreDataStack.resetStores([url, missing])

        for file in CoreDataStack.storeFiles(for: url) + CoreDataStack.storeFiles(for: missing) {
            #expect(!FileManager.default.fileExists(atPath: file.path), "\(file.lastPathComponent) is left")
        }
    }

    // MARK: - #13 The fallback chain

    @Test("The separate local store opens only on a device with neither split store")
    func separateLocalStoreOnlyWithoutSplitStores() {
        #expect(AppBootstrapping.mayOpenSeparateLocalStore(privateStoreExists: false, sharedStoreExists: false))
        #expect(!AppBootstrapping.mayOpenSeparateLocalStore(privateStoreExists: true, sharedStoreExists: false))
        #expect(!AppBootstrapping.mayOpenSeparateLocalStore(privateStoreExists: false, sharedStoreExists: true))
        #expect(!AppBootstrapping.mayOpenSeparateLocalStore(privateStoreExists: true, sharedStoreExists: true))
    }

    @Test("Every way Core Data says it can't open these bytes ends the fallback chain")
    func unopenableCodesAreFatal() {
        let codes = [134_020, 134_100, 134_110, 134_111, 134_120, 134_130, 134_140,
                     134_150, 134_160, 134_170, 134_190, 134_505, 134_506]
        for code in codes {
            let error = NSError(domain: NSCocoaErrorDomain, code: code)
            #expect(AppBootstrapping.isFatalStoreError(error), "\(code)")
            #expect(AppBootstrapping.isUnrecoverableStoreError(CoreDataStackError.cloudKitLoadFailed(error)))
        }
        // A CloudKit setup failure or a plain open error is ridden out by the chain.
        #expect(!AppBootstrapping.isFatalStoreError(NSError(domain: NSCocoaErrorDomain, code: 134_060)))
        #expect(!AppBootstrapping.isFatalStoreError(NSError(domain: NSCocoaErrorDomain, code: 134_080)))
        #expect(!AppBootstrapping.isFatalStoreError(NSError(domain: "Other", code: 134_110)))
        #expect(AppBootstrapping.isUnrecoverableStoreError(CoreDataStackError.storeInUseByAnotherCopy))
    }
}
