import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-02, #52, #54 and #55.
//
// #52: a notebook's shared store whose tables didn't match its metadata was
// moved aside without a word, rows and all; one that holds rows now stops the
// launch on the error screen, and only an empty one is moved aside.
// #54: a second copy waited ten seconds for a copy mid-migration, then told
// the guide to quit it; it now waits as long as a big migration takes.
// #55: Re-download, migrations and the error screen's restore left whole
// copies of the notebook on the device for good.

@Suite("Store files: rows, the launch's wait, and copies left behind")
@MainActor
struct StoreLeftoversTests {

    private func touch(_ url: URL) throws {
        try Data("x".utf8).write(to: url)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - #52

    @Test("A store with rows holds rows; an empty one, or none at all, doesn't")
    func storeHoldsRowsReadsTheTables() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let model = StoreFileFixture.model()
        let full = try StoreFileFixture.makeStore(at: fixture.url("full.sqlite"), model: model, rows: 2)
        let empty = try StoreFileFixture.makeStore(at: fixture.url("empty.sqlite"), model: model, rows: 0)

        #expect(CoreDataStack.storeHoldsRows(storeURL: full, configuration: nil, model: model))
        #expect(!CoreDataStack.storeHoldsRows(storeURL: empty, configuration: nil, model: model))
        #expect(!CoreDataStack.storeHoldsRows(storeURL: fixture.url("none.sqlite"), configuration: nil, model: model))
    }

    @Test("A file that can't be read as a store counts as holding rows")
    func unreadableStoreCountsAsHoldingRows() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let junk = fixture.url("junk.sqlite")
        try Data(repeating: 0x5A, count: 4096).write(to: junk)
        #expect(CoreDataStack.storeHoldsRows(storeURL: junk, configuration: nil, model: StoreFileFixture.model()))
    }

    // MARK: - #54

    @Test("A launch beside a copy mid-migration waits for it to finish, then opens without surgery")
    func launchWaitsOutAnotherCopysMigration() async throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let migrating = StoreProcessLock(directory: fixture.directory)
        let launching = StoreProcessLock(directory: fixture.directory)
        defer { migrating.close(); launching.close() }
        #expect(migrating.tryExclusive())

        // The migration takes longer than a moment; the launch waits it out.
        let release = Task.detached {
            try await Task.sleep(for: .milliseconds(400))
            migrating.releaseExclusive()
        }
        let opened = try await Task.detached {
            try CoreDataStack.claimStoresForLaunch(lock: launching, wait: .seconds(30))
        }.value
        try await release.value

        #expect(!opened, "opens beside the other copy, without surgery")
        #expect(!launching.holdsExclusive)
        // Ten seconds was shorter than a big notebook's migration and its copy.
        #expect(CoreDataStack.storeLockWait >= .seconds(5 * 60))
    }

    // MARK: - #55 Re-download

    @Test("Re-download removes the copy made before a migration, a quarantined store and the attachments folder")
    func resetRemovesLeftoverCopies() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let model = StoreFileFixture.model()
        let url = try StoreFileFixture.makeStore(at: fixture.url("private.sqlite"), model: model, rows: 1)
        let premigration = try #require(CoreDataStack.backUpStoreBeforeMigration(storeURL: url, model: model))
        try touch(CoreDataStack.quarantineURL(for: url))
        try touch(URL(fileURLWithPath: CoreDataStack.quarantineURL(for: url).path + "-wal"))
        let support = fixture.url(".private_SUPPORT")
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent("_EXTERNAL_DATA"), withIntermediateDirectories: true
        )
        try touch(support.appendingPathComponent("_EXTERNAL_DATA/photo"))
        // Another store's things stay.
        let other = fixture.url("other.premigration.sqlite")
        try touch(other)

        #expect(premigration == CoreDataStack.premigrationCopyURL(for: url))
        #expect(exists(premigration))

        try CoreDataStack.resetStores([url])

        for item in CoreDataStack.storeFiles(for: url) + CoreDataStack.leftoverStoreItems(for: url) {
            #expect(!exists(item), "\(item.lastPathComponent) is left")
        }
        #expect(exists(other))
    }

    @Test("A Re-download with the store already gone still removes what it left")
    func resetRemovesLeftoversOfAMissingStore() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let url = fixture.url("shared.sqlite")
        let quarantined = CoreDataStack.quarantineURL(for: url)
        try touch(quarantined)

        try CoreDataStack.resetStores([url])

        #expect(!exists(quarantined))
        #expect(!exists(url), "no empty store is made in its place")
    }

    // MARK: - #55 After a migration

    @Test("Once the stores have opened, the copies made before a migration go; other files stay")
    func premigrationCopiesGoAfterLoad() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let model = StoreFileFixture.model()
        let url = try StoreFileFixture.makeStore(at: fixture.url("thing.sqlite"), model: model, rows: 2)
        let copy = try #require(CoreDataStack.backUpStoreBeforeMigration(storeURL: url, model: model))
        #expect(exists(copy))

        CoreDataStack.removePremigrationCopies(of: [url, fixture.url("never-made.sqlite")])

        for file in CoreDataStack.storeFiles(for: copy) {
            #expect(!exists(file), "\(file.lastPathComponent) is left")
        }
        #expect(StoreFileFixture.rowCount(at: url) == 2, "the store itself is untouched")
    }

    // MARK: - #55 The error screen's restore

    @Test("A notebook a restore set aside goes after a month; a newer one, and other folders, stay")
    func setAsideNotebooksAreTrimmedAfterAMonth() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z"))
        let day: TimeInterval = 24 * 60 * 60
        let old = FreshNotebookRestore.keptFolderName(at: now.addingTimeInterval(-40 * day))
        let oldSecond = old + " 2"
        let recent = FreshNotebookRestore.keptFolderName(at: now.addingTimeInterval(-10 * day))
        for name in [old, oldSecond, recent, "Set aside by hand", "Restoring"] {
            let folder = fixture.url(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try touch(folder.appendingPathComponent("private.sqlite"))
        }

        let deleted = CoreDataStack.trimSetAsideNotebooks(in: fixture.directory, now: now, syncIsOn: true)

        #expect(Set(deleted) == [old, oldSecond])
        #expect(!exists(fixture.url(old)))
        #expect(!exists(fixture.url(oldSecond)))
        for name in [recent, "Set aside by hand", "Restoring"] {
            #expect(exists(fixture.url(name)), "\(name) was removed")
        }
    }

    @Test("Nothing set aside goes while a restore is unfinished")
    func unfinishedRestoreKeepsEverything() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let now = Date()
        let old = FreshNotebookRestore.keptFolderName(at: now.addingTimeInterval(-90 * 24 * 60 * 60))
        try FileManager.default.createDirectory(at: fixture.url(old), withIntermediateDirectories: true)
        try old.write(
            to: fixture.url(CoreDataStack.unfinishedRestoreMarkerName), atomically: true, encoding: .utf8
        )

        #expect(CoreDataStack.trimSetAsideNotebooks(in: fixture.directory, now: now, syncIsOn: true).isEmpty)
        #expect(exists(fixture.url(old)))
    }

    @Test("Nothing set aside goes while iCloud sync is off, however old; once it's on, the old one goes")
    func syncOffKeepsEverySetAsideNotebook() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z"))
        let old = FreshNotebookRestore.keptFolderName(at: now.addingTimeInterval(-400 * 24 * 60 * 60))
        try FileManager.default.createDirectory(at: fixture.url(old), withIntermediateDirectories: true)
        try touch(fixture.url(old).appendingPathComponent("private.sqlite"))

        // The error screen's restore runs only with sync off, and the notebook
        // it set aside may hold the only copy of work done since the backup.
        #expect(CoreDataStack.trimSetAsideNotebooks(in: fixture.directory, now: now, syncIsOn: false).isEmpty)
        #expect(exists(fixture.url(old)))

        #expect(CoreDataStack.trimSetAsideNotebooks(in: fixture.directory, now: now, syncIsOn: true) == [old])
        #expect(!exists(fixture.url(old)))
    }

    @Test("The restored screen says how long the set-aside notebook is kept")
    func restoredMessageSaysHowLong() {
        let words = DatabaseErrorCoordinator.restoredMessage(warnings: [])
        #expect(words.contains("while it's off"))
        #expect(words.contains("a month old"))
    }

    @Test("The set-aside date reads back from the restore's own folder name")
    func setAsideDateRoundTrips() throws {
        let when = try #require(ISO8601DateFormatter().date(from: "2026-03-04T05:06:07Z"))
        let name = FreshNotebookRestore.keptFolderName(at: when)
        #expect(CoreDataStack.setAsideDate(folderName: name) == when)
        #expect(CoreDataStack.setAsideDate(folderName: name + " 3") == when)
        #expect(CoreDataStack.setAsideDate(folderName: "Restoring") == nil)
        #expect(CoreDataStack.setAsideDate(folderName: "Set aside later") == nil)
    }
}
