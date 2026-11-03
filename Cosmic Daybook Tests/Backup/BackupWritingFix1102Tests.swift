import CoreData
import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-02 (sync, sharing and backups), the backup-writing
// findings: dates kept to the millisecond (#20), one backup key per device
// that made one, every key kept for reading and none made during a first
// download (#15), temp files a killed export left behind removed (#17),
// another device's backups not downloaded here still found (#18), backups of
// a half-downloaded notebook marked Partial- and kept apart (#14), this
// device's failing automatic backups surfaced (#12), and a size estimate
// that counts every type (#21).

/// Backup keys held in memory: what `BackupEncryptionKeyStore.$items` reads
/// in these tests, never the real Keychain.
nonisolated final class Fix1102KeyBox: Sendable {
    private let keys: Mutex<[BackupEncryptionKeyStore.StoredKey]>

    init(_ keys: [BackupEncryptionKeyStore.StoredKey] = []) {
        self.keys = Mutex(keys)
    }

    var accounts: [String] { keys.withLock { $0.map(\.account) } }

    func add(_ key: BackupEncryptionKeyStore.StoredKey) {
        keys.withLock { list in
            guard !list.contains(where: { $0.account == key.account }) else { return }
            list.append(key)
        }
    }

    var items: BackupEncryptionKeyStore.Items {
        BackupEncryptionKeyStore.Items(
            list: { self.keys.withLock { $0 } },
            add: { self.add($0) }
        )
    }

    static func key(madeAt date: Date) -> BackupEncryptionKeyStore.StoredKey {
        .init(account: BackupEncryptionKeyStore.stampedAccount(madeAt: date), key: SymmetricKey(size: .bits256))
    }

    static func legacyKey() -> BackupEncryptionKeyStore.StoredKey {
        .init(account: BackupEncryptionKeyStore.legacyAccount, key: SymmetricKey(size: .bits256))
    }
}

/// Scratch folders and files for the Fix1102 suites.
enum Fix1102Fixtures {
    /// A scratch folder, removed afterwards.
    static func withFolder<R>(_ body: (URL) async throws -> R) async throws -> R {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupWritingFix1102-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try await body(folder)
    }

    static func touch(_ url: URL, modified date: Date) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// A notebook in memory with one student, saved.
    @MainActor
    static func notebookWithOneStudent() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        #expect(CoreDataTestHelpers.save(context))
        return context
    }
}

// MARK: - Dates (#20)

@Suite("Backup dates (Fix1102 #20)")
struct BackupDateCodingFix1102Tests {

    private struct Row: Codable, Equatable {
        let date: Date
    }

    private let whole = Date(timeIntervalSince1970: 1_793_606_400) // 2026-11-02T08:00:00Z

    private func encode(_ row: Row, _ strategy: JSONEncoder.DateEncodingStrategy) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = strategy
        return String(bytes: try encoder.encode(row), encoding: .utf8) ?? ""
    }

    private func decode(_ json: String) throws -> Row {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = BackupDateCoding.decodingStrategy
        return try decoder.decode(Row.self, from: Data(json.utf8))
    }

    @Test("A whole-second date is written exactly as older builds wrote it")
    func wholeSecondsUnchanged() throws {
        #expect(BackupDateCoding.string(from: whole) == "2026-11-02T08:00:00Z")
        #expect(try encode(Row(date: whole), BackupDateCoding.encodingStrategy) == encode(Row(date: whole), .iso8601))
    }

    @Test("A date's milliseconds are kept, and both forms read back")
    func fractionKept() throws {
        let precise = whole.addingTimeInterval(0.123)
        #expect(BackupDateCoding.string(from: precise) == "2026-11-02T08:00:00.123Z")

        let json = try encode(Row(date: precise), BackupDateCoding.encodingStrategy)
        let read = try decode(json)
        #expect(abs(read.date.timeIntervalSince(precise)) < 0.001)
        #expect(read.date != whole, "the fraction survives the round trip")

        // An older archive's whole-second date.
        #expect(try decode(#"{"date":"2026-11-02T08:00:00Z"}"#) == Row(date: whole))
        #expect(throws: DecodingError.self) { try decode(#"{"date":"last Tuesday"}"#) }
    }

    @Test("A reader still on JSONDecoder's .iso8601 reads a date with milliseconds too")
    func plainISO8601ReaderKeepsUp() throws {
        // The restore's own decoders move to BackupDateCoding separately; until
        // then they must still read what the writer now writes.
        let precise = whole.addingTimeInterval(0.123)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = try encode(Row(date: precise), BackupDateCoding.encodingStrategy)
        let read = try decoder.decode(Row.self, from: Data(json.utf8))
        #expect(abs(read.date.timeIntervalSince(precise)) < 0.001)
    }
}

// MARK: - Backup keys (#15)

@Suite("Backup keys (Fix1102 #15)", .serialized)
struct BackupKeysFix1102Tests {

    private typealias Store = BackupEncryptionKeyStore

    @Test("No key is made during a first download; one is made after, stamped with when")
    func noKeyMadeDuringFirstDownload() throws {
        let box = Fix1102KeyBox()
        let made = Date(timeIntervalSinceReferenceDate: 815_299_200)
        try Store.$items.withValue(box.items) {
            let error = #expect(throws: Store.KeyStoreError.self) {
                try Store.fetchOrCreateKey(firstDownloadPending: true, now: made)
            }
            guard case .keyNotHereYet? = error else {
                Issue.record("expected keyNotHereYet, got \(String(describing: error))")
                return
            }
            #expect(box.accounts.isEmpty, "nothing added to the Keychain")

            let key = try Store.fetchOrCreateKey(firstDownloadPending: false, now: made)
            let account = try #require(box.accounts.first)
            #expect(box.accounts.count == 1)
            #expect(account.hasPrefix("backup-archive-key-v2."))
            #expect(Store.madeAt(account) == made)

            // Once there is a key, a first download doesn't stop it being used.
            #expect(try Store.fetchOrCreateKey(firstDownloadPending: true) == key)
            #expect(box.accounts.count == 1, "no second key made")
        }
    }

    @Test("Every device writes with the oldest key: the v1 one, then the earliest stamped")
    func oldestKeyWrites() throws {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSinceReferenceDate: 815_299_200)
        let later = Fix1102KeyBox.key(madeAt: base.addingTimeInterval(day))
        let earlier = Fix1102KeyBox.key(madeAt: base)
        let unreadable = Store.StoredKey(account: "backup-archive-key-v9.someday", key: SymmetricKey(size: .bits256))
        let legacy = Fix1102KeyBox.legacyKey()

        let ordered = Store.ordered([later, unreadable, legacy, earlier]).map(\.account)
        #expect(ordered == [legacy.account, earlier.account, later.account, unreadable.account])

        let box = Fix1102KeyBox([later, earlier])
        try Store.$items.withValue(box.items) { () throws in
            #expect(try Store.fetchOrCreateKey(firstDownloadPending: false) == earlier.key)
            #expect(try Store.requireKey() == earlier.key)
            box.add(legacy)
            #expect(try Store.fetchOrCreateKey(firstDownloadPending: false) == legacy.key)
            #expect(try Store.readingKeys() == [legacy.key, earlier.key, later.key])
        }
    }

    @Test("A backup made with another device's key opens once both keys are here")
    @MainActor
    func archiveFromTheOtherKeyOpens() async throws {
        let context = try Fix1102Fixtures.notebookWithOneStudent()
        let newDevices = Fix1102KeyBox.key(madeAt: Date())
        let older = Fix1102KeyBox.legacyKey()
        try await Fix1102Fixtures.withFolder { folder in
            let url = folder.appendingPathComponent("Backup.\(BackupFile.fileExtension)")
            // A new device, before iCloud Keychain brought the older key.
            let box = Fix1102KeyBox([newDevices])
            try await Store.$items.withValue(box.items) {
                _ = try await BackupWriter.write(viewContext: context, to: url, includesPhotos: false)
            }

            // Only the older key: the backup can't be opened.
            Store.$items.withValue(Fix1102KeyBox([older]).items) {
                #expect(throws: (any Error).self) { try BackupReader.read(from: url) }
            }

            // The older key arrives: it's the one to write with now, and the
            // backup made with the new device's key still opens.
            box.add(older)
            try Store.$items.withValue(box.items) {
                #expect(try Store.requireKey() == older.key)
                let backup = try BackupReader.read(from: url)
                #expect(backup.manifest.entityCounts["Student"] == 1)
                #expect(try BackupReader.verifyStructure(at: url).manifest.entityCounts["Student"] == 1)
            }
        }
    }
}

// MARK: - Temp files a killed export left (#17)

@Suite("Abandoned backup temp files (Fix1102 #17)", .serialized)
struct BackupTempFilesFix1102Tests {

    @Test("A temp file an hour old goes; a fresh one, and anything else, stays")
    func abandonedTempFilesGo() async throws {
        try await Fix1102Fixtures.withFolder { folder in
            let now = Date()
            let backup = folder.appendingPathComponent("AutoBackup-1.\(BackupFile.fileExtension)")
            let abandoned = BackupWriter.tempFileURL(for: backup)
            let writing = BackupWriter.tempFileURL(for: backup)
            let someoneElses = folder.appendingPathComponent(".Notes.txt.partial-\(UUID().uuidString)")
            let finished = folder.appendingPathComponent("AutoBackup-2.\(BackupFile.fileExtension)")
            try Fix1102Fixtures.touch(abandoned, modified: now.addingTimeInterval(-2 * 3_600))
            try Fix1102Fixtures.touch(writing, modified: now.addingTimeInterval(-10 * 60))
            try Fix1102Fixtures.touch(someoneElses, modified: now.addingTimeInterval(-2 * 3_600))
            try Fix1102Fixtures.touch(finished, modified: now.addingTimeInterval(-2 * 3_600))

            #expect(BackupWriter.isTempFileName(abandoned.lastPathComponent))
            #expect(!BackupWriter.isTempFileName(someoneElses.lastPathComponent))
            #expect(!BackupWriter.isTempFileName(finished.lastPathComponent))

            let removed = BackupWriter.removeAbandonedTempFiles(in: folder, now: now) {
                try FileManager.default.removeItem(at: $0)
            }
            #expect(removed == 1)
            #expect(!Fix1102Fixtures.exists(abandoned))
            #expect(Fix1102Fixtures.exists(writing), "an export may still be writing it")
            #expect(Fix1102Fixtures.exists(someoneElses))
            #expect(Fix1102Fixtures.exists(finished))
        }
    }

    @Test("Each export clears the folder's abandoned temp files")
    @MainActor
    func exportClearsAbandonedTempFiles() async throws {
        let context = try Fix1102Fixtures.notebookWithOneStudent()
        try await Fix1102Fixtures.withFolder { folder in
            let url = folder.appendingPathComponent("ManualBackup-1.\(BackupFile.fileExtension)")
            let abandoned = BackupWriter.tempFileURL(for: folder.appendingPathComponent("AutoBackup-0.mtbbackup"))
            try Fix1102Fixtures.touch(abandoned, modified: Date().addingTimeInterval(-3 * 3_600))

            try await BackupEncryptionKeyStore.$items.withValue(Fix1102KeyBox([Fix1102KeyBox.legacyKey()]).items) {
                _ = try await BackupWriter.write(viewContext: context, to: url, includesPhotos: false)
            }
            #expect(Fix1102Fixtures.exists(url))
            #expect(!Fix1102Fixtures.exists(abandoned))
            let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(left == [url.lastPathComponent], "no temp file of its own left either")
        }
    }
}

// MARK: - iCloud files, listing and copying (#9, #18)

@Suite("iCloud backup files (Fix1102 #9 #18)", .serialized)
struct UbiquitousBackupFilesFix1102Tests {

    @Test("A listing names the iCloud files not downloaded here, by their real names, once")
    func listingIncludesPlaceholders() async throws {
        try await Fix1102Fixtures.withFolder { folder in
            let now = Date()
            try Fix1102Fixtures.touch(folder.appendingPathComponent("Here.mtbbackup"), modified: now)
            try Fix1102Fixtures.touch(folder.appendingPathComponent(".Elsewhere.mtbbackup.icloud"), modified: now)
            // A placeholder beside its own downloaded file, and a hidden file.
            try Fix1102Fixtures.touch(folder.appendingPathComponent(".Here.mtbbackup.icloud"), modified: now)
            try Fix1102Fixtures.touch(folder.appendingPathComponent(".DS_Store"), modified: now)

            let names = try UbiquitousFile.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .map(\.lastPathComponent)
            #expect(names.sorted() == ["Elsewhere.mtbbackup", "Here.mtbbackup"])
            #expect(UbiquitousFile.needsDownload(folder.appendingPathComponent("Elsewhere.mtbbackup")))
        }
    }

    @Test("A checked copy replaces the file in one step, or makes it, and leaves nothing beside it")
    func checkedCopyReplaces() async throws {
        try await Fix1102Fixtures.withFolder { folder in
            let source = folder.appendingPathComponent("Source.mtbbackup")
            try Data("the new backup".utf8).write(to: source)
            let saved = folder.appendingPathComponent("Saved", isDirectory: true)
            try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
            let existing = saved.appendingPathComponent("Backup.mtbbackup")
            try Data("an old backup, longer than the new one".utf8).write(to: existing)

            try UbiquitousFile.copyCheckedThenReplace(from: source, to: existing)
            #expect(try Data(contentsOf: existing) == Data("the new backup".utf8))

            let fresh = saved.appendingPathComponent("New.mtbbackup")
            try await UbiquitousFile.coordinatedCopy(from: source, replacing: fresh, timeout: .seconds(10))
            #expect(try Data(contentsOf: fresh) == Data("the new backup".utf8))
            #expect(Fix1102Fixtures.exists(source), "the source stays")
            #expect(try FileManager.default.contentsOfDirectory(atPath: saved.path).sorted()
                == ["Backup.mtbbackup", "New.mtbbackup"])
        }
    }
}
