import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Hunt of 2026-10-05, #9 (Phase 3). The "can't open notebook" screen's Restore
// Backup posted a route nothing handled. It now restores into a fresh notebook
// (`FreshNotebookRestore`): the notebook that wouldn't open is moved aside and
// kept, the backup opens in its place, and nothing from iCloud ever downloads
// into it. Every test works in a temporary folder with a lock of its own; none
// touches the app's store folder.

/// A store folder with its own lock and a defaults suite, thrown away after.
@MainActor
private final class ErrorScreenRestoreScene {
    static let now = Date(timeIntervalSince1970: 1_791_300_000)

    let fixture: StoreFileFixture
    let lock: StoreProcessLock
    let suiteName = "ErrorScreenRestoreTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    /// The notebook that wouldn't open: what each of its files held.
    private(set) var failedFiles: [String: Data] = [:]

    init() throws {
        fixture = try StoreFileFixture()
        lock = StoreProcessLock(directory: fixture.directory)
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: UserDefaultsKeys.enableCloudKitSync)
    }

    var directory: URL { fixture.directory }

    func cleanUp() {
        lock.close()
        defaults.removePersistentDomain(forName: suiteName)
        fixture.cleanUp()
    }

    /// Store files no build can open: bytes that aren't a database, a
    /// journal, and an attachment in Core Data's folder beside them.
    func makeUnopenableNotebook() throws {
        let files: [String: Data] = [
            "private.sqlite": Data("not a database: the notebook that wouldn't open".utf8),
            "private.sqlite-wal": Data("its journal".utf8),
            ".private_SUPPORT/_EXTERNAL_DATA/attachment": Data(repeating: 7, count: 2_048),
            "shared.sqlite": Data("not a database either".utf8)
        ]
        for (path, data) in files {
            let url = directory.appendingPathComponent(path)
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
        }
        failedFiles = files
    }

    /// Whether every file of the notebook that wouldn't open is in `folder`,
    /// byte for byte.
    func holdsFailedNotebook(_ folder: URL) -> Bool {
        failedFiles.allSatisfy { path, data in
            (try? Data(contentsOf: folder.appendingPathComponent(path))) == data
        }
    }

    /// The folders beside the stores, other than Core Data's own.
    func otherFolders() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { name in
            var isFolder: ObjCBool = false
            let path = directory.appendingPathComponent(name).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
                && isFolder.boolValue && !name.hasSuffix("_SUPPORT")
        }.sorted()
    }

    func restore(
        isOpenInThisCopy: @escaping @MainActor (URL) -> Bool = { _ in false },
        moveFile: @escaping @MainActor (URL, URL) throws -> Void = FreshNotebookRestore.moveFileNormally
    ) throws -> FreshNotebookRestore {
        FreshNotebookRestore(
            lock: lock,
            defaults: defaults,
            model: try CoreDataStack.sharedModel(),
            isOpenInThisCopy: isOpenInThisCopy,
            moveFile: moveFile,
            now: Self.now
        )
    }

    func coordinator() -> BackupCoordinator {
        BackupCoordinator(
            backupService: BackupService(), transactionManager: BackupTransactionManager(),
            appRouter: AppRouter(), restoreGateDefaults: defaults
        )
    }

    func run(_ restore: FreshNotebookRestore, backup url: URL) async throws -> FreshNotebookRestore.Result {
        try await restore.run(backup: url, restoringWith: coordinator(), progress: { _, _ in })
    }

    // MARK: Backups

    /// Ink big enough that Core Data keeps it outside the database.
    static let bigInk = Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    struct Backup {
        let store: BackupStreamingFixtures.Store
        let url: URL
        let inkID: UUID
    }

    /// A backup of every type plus one page of `bigInk`.
    static func makeBackup() async throws -> Backup {
        let store = try BackupStreamingFixtures.makeStore()
        try BackupStreamingFixtures.seedEveryType(in: store.context, bulk: 0)
        let ink = CDAlbumPageInk(context: store.context)
        ink.albumID = "math-album"
        ink.pageIndex = 12
        ink.drawingData = bigInk
        try store.context.save()
        let url = store.archiveURL("Source")
        try await BackupRestoreFixtures.writeBackup(of: store.context, to: url)
        return Backup(store: store, url: url, inkID: try #require(ink.id))
    }

    /// The restored notebook in `directory`, opened as a launch with iCloud
    /// sync off opens the app's stores.
    static func openRestored(in directory: URL) throws -> NSPersistentContainer {
        let model = try CoreDataStack.sharedModel()
        let container = NSPersistentContainer(name: CoreDataStack.modelName, managedObjectModel: model)
        container.persistentStoreDescriptions = FreshNotebookRestore.storeDescriptions(in: directory)
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError { throw loadError }
        return container
    }
}

@Suite("Restore from the error screen", .serialized)
@MainActor
struct ErrorScreenRestoreTests {
    private typealias Restore = BackupRestoreFixtures
    private typealias Scene = ErrorScreenRestoreScene

    // MARK: - What the screen offers

    @Test("With iCloud sync on the screen says to re-download first; with it off it offers the restore")
    func offerFollowsSync() {
        let failed = CoreDataStackError.storeLoadFailed(NSError(domain: NSCocoaErrorDomain, code: NSMigrationError))
        #expect(DatabaseErrorCoordinator.restoreOffer(for: failed, syncPreferred: false) == .button)
        #expect(
            DatabaseErrorCoordinator.restoreOffer(for: failed, syncPreferred: true)
                == .guidance(FreshNotebookRestore.syncOnGuidance)
        )
        let damaged = CoreDataStackError.storeSchemaIncoherent(storeName: "private.sqlite", detail: "x")
        #expect(DatabaseErrorCoordinator.restoreOffer(for: damaged, syncPreferred: false) == .button)

        let nothing: [CoreDataStackError] = [
            .storeFromNewerBuild(storeName: "private.sqlite", storeVersion: 17, appVersion: 16),
            .storeInUseByAnotherCopy,
            .modelNotFound("CosmicDaybook")
        ]
        for error in nothing {
            #expect(DatabaseErrorCoordinator.restoreOffer(for: error, syncPreferred: false) == .hidden)
            #expect(DatabaseErrorCoordinator.restoreOffer(for: error, syncPreferred: true) == .hidden)
        }

        let words = FreshNotebookRestore.syncOnGuidance + DatabaseErrorCoordinator.restoredMessage(warnings: [])
        #expect(words.contains("Re-download from iCloud"))
        #expect(words.contains("Settings \u{203A} Sync and backup"))
        // Whole words: "restore" is fine, "store" isn't.
        for jargon in ["sqlite", "store", "CloudKit", "cache", "staging"] {
            let found = words.range(of: "\\b\(jargon)\\b", options: [.regularExpression, .caseInsensitive])
            #expect(found == nil, "\(jargon)")
        }
    }

    @Test("The fresh notebook is made as a launch with iCloud sync off makes the app's stores, without iCloud")
    func freshNotebookHasNoICloud() {
        let folder = URL(fileURLWithPath: "/tmp/fresh")
        let fresh = FreshNotebookRestore.storeDescriptions(in: folder)
        let launch = CoreDataStack.makeStoreDescriptions(
            enableCloudKit: false, inMemory: false, preserveSplitStoreLayout: true, localStoreURL: nil
        )
        let freshConfigurations: [String?] = fresh.map(\.configuration)
        let launchConfigurations: [String?] = launch.map(\.configuration)
        #expect(freshConfigurations == launchConfigurations)
        let freshNames: [String] = fresh.compactMap { $0.url?.lastPathComponent }
        let launchNames: [String] = launch.compactMap { $0.url?.lastPathComponent }
        #expect(freshNames == launchNames)
        let freshFolders: [String] = fresh.compactMap { $0.url?.deletingLastPathComponent().path }
        #expect(freshFolders == [folder.path, folder.path])
        let freshTypes: [String] = fresh.map(\.type)
        let launchTypes: [String] = launch.map(\.type)
        #expect(freshTypes == launchTypes)
        for (made, opened) in zip(fresh, launch) {
            #expect(made.cloudKitContainerOptions == nil)
            #expect(NSDictionary(dictionary: made.options) == NSDictionary(dictionary: opened.options))
        }
        #expect(CoreDataStack.privateStoreURL().lastPathComponent == FreshNotebookRestore.stores[0].fileName)
        #expect(CoreDataStack.sharedStoreURL().lastPathComponent == FreshNotebookRestore.stores[1].fileName)
        // A restore never turns sync on: it isn't a setting backups carry.
        #expect(!BackupPreferencesService.isBackedUp(UserDefaultsKeys.enableCloudKitSync))
    }

    // MARK: - Restoring

    @Test("The notebook that wouldn't open is kept whole, and the backup opens in its place without iCloud")
    func restoresAndKeeps() async throws {
        let scene = try Scene()
        defer { scene.cleanUp() }
        try scene.makeUnopenableNotebook()
        let backup = try await Scene.makeBackup()
        defer { backup.store.remove() }
        // The device's flags belong to the notebook that wouldn't open: its
        // first download, and its history positions.
        FirstDownloadGate.arm(defaults: scene.defaults)
        scene.defaults.set(["private": Data([1])], forKey: UserDefaultsKeys.persistentHistoryStoreTokens)

        let result = try await scene.run(scene.restore(), backup: backup.url)

        let kept = try #require(result.keptFolder)
        #expect(kept.lastPathComponent == FreshNotebookRestore.keptFolderName(at: Scene.now))
        #expect(scene.holdsFailedNotebook(kept), "every file of the old notebook, byte for byte")
        #expect(try scene.otherFolders() == [kept.lastPathComponent], "nothing else left beside the stores")
        #expect(scene.defaults.object(forKey: UserDefaultsKeys.persistentHistoryStoreTokens) == nil)
        #expect(!CoreDataStack.syncPreferred(in: scene.defaults), "sync stays off")
        #expect(!scene.lock.holdsExclusive)

        // The restored notebook passes the launch's checks and opens.
        let model = try CoreDataStack.sharedModel()
        for store in FreshNotebookRestore.stores {
            let storeURL = scene.directory.appendingPathComponent(store.fileName)
            try CoreDataStack.verifyStoreIsNotFromNewerBuild(storeURL: storeURL)
            #expect(StoreFileFixture.stamp(at: storeURL) == CoreDataStack.currentSchemaVersion)
            let configuration = store.configuration
            #expect(!CoreDataStack.storeNeedsMigration(storeURL: storeURL, configuration: configuration, model: model))
            #expect(
                CoreDataStack.incoherentSchemaFindings(storeURL: storeURL, configuration: configuration, model: model)
                    .isEmpty
            )
            // Nothing of iCloud's was ever set up in it.
            #expect(!StoreFileFixture.execute(at: storeURL, "SELECT 1 FROM ANSCKRECORDMETADATA LIMIT 1"))
        }
        let restored = try Scene.openRestored(in: scene.directory)
        defer {
            let coordinator = restored.persistentStoreCoordinator
            for store in coordinator.persistentStores { try? coordinator.remove(store) }
        }

        // The same records as the backup restored the usual way…
        let usual = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await Restore.restore(backup.url, into: usual.viewContext, mode: .merge)
        try Restore.expectSameStore(restored.viewContext, usual.viewContext, "fresh notebook")
        // …the ink Core Data keeps outside the database included.
        let inkRequest = NSFetchRequest<NSManagedObject>(entityName: "AlbumPageInk")
        inkRequest.predicate = NSPredicate(format: "id == %@", backup.inkID as CVarArg)
        let ink = try #require(try restored.viewContext.fetch(inkRequest).first)
        #expect(ink.value(forKey: "drawingData") as? Data == Scene.bigInk)
        let external = scene.directory.appendingPathComponent(".private_SUPPORT/_EXTERNAL_DATA")
        #expect(try !FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }

    @Test("A restore that fails leaves the notebook that wouldn't open where it was")
    func failedRestoreLeavesNotebook() async throws {
        let scene = try Scene()
        defer { scene.cleanUp() }
        try scene.makeUnopenableNotebook()
        let notABackup = scene.fixture.url("Damaged.\(BackupFile.fileExtension)")
        try Data("not a backup".utf8).write(to: notABackup)
        scene.defaults.set(["private": Data([1])], forKey: UserDefaultsKeys.persistentHistoryStoreTokens)

        await #expect(throws: (any Error).self) {
            try await scene.run(scene.restore(), backup: notABackup)
        }

        #expect(scene.holdsFailedNotebook(scene.directory))
        #expect(try scene.otherFolders().isEmpty, "no kept folder and no half-made notebook")
        #expect(scene.defaults.object(forKey: UserDefaultsKeys.persistentHistoryStoreTokens) != nil)
        #expect(!scene.lock.holdsExclusive)
    }

    @Test("If the restored notebook can't be moved into place, every file goes back")
    func failedSwapPutsEverythingBack() async throws {
        let scene = try Scene()
        defer { scene.cleanUp() }
        try scene.makeUnopenableNotebook()
        let backup = try await Scene.makeBackup()
        defer { backup.store.remove() }
        // The old notebook moves aside; then the new one's shared store won't move in.
        let restore = try scene.restore(moveFile: { from, to in
            let staged = from.path.contains("/\(FreshNotebookRestore.stagingFolderName)/")
            if staged, from.lastPathComponent == "shared.sqlite" {
                throw CocoaError(.fileWriteUnknown)
            }
            try FreshNotebookRestore.moveFileNormally(from, to)
        })

        await #expect(throws: FreshNotebookRestore.Failure.couldNotSwap) {
            try await scene.run(restore, backup: backup.url)
        }

        #expect(scene.holdsFailedNotebook(scene.directory))
        #expect(try scene.otherFolders().isEmpty)
    }

    @Test("Refused, with nothing moved: iCloud sync on, another copy open, this copy has it open, already running")
    func refusals() async throws {
        let scene = try Scene()
        defer { scene.cleanUp() }
        try scene.makeUnopenableNotebook()
        let backup = try await Scene.makeBackup()
        defer { backup.store.remove() }

        // iCloud sync on (unset reads as on): the next launch would download into it.
        scene.defaults.removeObject(forKey: UserDefaultsKeys.enableCloudKitSync)
        await #expect(throws: FreshNotebookRestore.Failure.syncIsOn) {
            try await scene.run(scene.restore(), backup: backup.url)
        }
        scene.defaults.set(false, forKey: UserDefaultsKeys.enableCloudKitSync)

        // Another copy of the app holds the stores.
        let otherCopy = StoreProcessLock(directory: scene.directory)
        #expect(otherCopy.holdShared(timeout: .zero))
        await #expect(throws: FreshNotebookRestore.Failure.anotherCopyOpen) {
            try await scene.run(scene.restore(), backup: backup.url)
        }
        otherCopy.close()

        // This copy has the notebook open after all (a simulated failure).
        await #expect(throws: FreshNotebookRestore.Failure.notebookOpen) {
            let restore = try scene.restore(isOpenInThisCopy: { $0.lastPathComponent == "private.sqlite" })
            return try await scene.run(restore, backup: backup.url)
        }

        // Surgery already under way in this copy.
        #expect(scene.lock.tryExclusive())
        await #expect(throws: FreshNotebookRestore.Failure.alreadyRunning) {
            try await scene.run(scene.restore(), backup: backup.url)
        }
        scene.lock.releaseExclusive()

        #expect(scene.holdsFailedNotebook(scene.directory))
        #expect(try scene.otherFolders().isEmpty)
    }

    // MARK: - The gate

    @Test("The first-download refusal is waived for the fresh notebook only; the lead-guide check isn't")
    func firstDownloadWaivedForFreshNotebookOnly() async throws {
        let scene = try Scene()
        defer { scene.cleanUp() }
        FirstDownloadGate.arm(defaults: scene.defaults)
        let (source, url) = try await Restore.makeBackup(bulk: 0)
        defer { source.remove() }

        let open = try CoreDataTestHelpers.makeInMemoryStack()
        await #expect(throws: BackupRestoreGate.Refusal.self) {
            try await scene.coordinator().importBackup(
                viewContext: open.viewContext, from: url, mode: .merge, progress: { _, _ in }
            )
        }
        #expect(try Restore.snapshot(of: open.viewContext).isEmpty)

        let fresh = try CoreDataTestHelpers.makeInMemoryStack()
        try await scene.coordinator().importBackup(
            viewContext: fresh.viewContext, from: url, mode: .merge, target: .freshNotebook, progress: { _, _ in }
        )
        #expect(try BackupTestUtil.count(entityName: "Student", in: fresh.viewContext) > 0)

        let assistants = try CoreDataTestHelpers.makeInMemoryStack()
        CoreDataTestHelpers.seedClassroomMembership(in: assistants.viewContext, role: .assistant)
        try assistants.viewContext.save()
        do {
            try await scene.coordinator().importBackup(
                viewContext: assistants.viewContext, from: url, mode: .merge, target: .freshNotebook,
                progress: { _, _ in }
            )
            Issue.record("An assistant's notebook should have been refused")
        } catch let refusal as BackupRestoreGate.Refusal {
            #expect(refusal.reason == BackupRestoreGate.notLeadGuide)
        }
    }
}
