import CoreData
import Foundation
import SQLite3
import Testing
@testable import CosmicDaybook

// Schema 23 dropped the track enrollments and `Note.studentTrackEnrollmentID`.
// `EnrollmentNoteOwners` reads whose each enrollment note is from the SQLite
// file before the store migrates, and the launch pass narrows each such note
// that names no child to that child (`docs/Plans/Plan - Retire the track
// entities.md`, Phase 3). `TrackEntitiesDropMigrationTests` runs the whole
// path on a schema-22 store; these hold the two halves to their rules.

@Suite("Enrollment notes join their child (schema 23)")
@MainActor
struct EnrollmentNoteOwnersTests {

    private let child = UUID()
    private let classmate = UUID()

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "EnrollmentNoteOwnersTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    private func note(_ scope: NoteScope, in context: NSManagedObjectContext) throws -> CDNote {
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Ready for the next fraction")
        note.id = UUID()
        note.scope = scope
        return note
    }

    // MARK: - After the store loads

    @Test("A waiting note that names no child moves to her; one that names a child or a list keeps its scope")
    func applyNarrowsOnlyNotesWithNoChild() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()
        let wholeClass = try note(.all, in: context)
        let nobody = try note(.students([]), in: context)
        let namesClassmate = try note(.student(classmate), in: context)
        let two = [classmate, UUID()]
        let namesTwo = try note(.students(two), in: context)
        let notWaiting = try note(.all, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let waiting = [wholeClass, nobody, namesClassmate, namesTwo]
        defaults.set(
            Dictionary(uniqueKeysWithValues: try waiting.map { (try #require($0.id).uuidString, child.uuidString) }),
            forKey: EnrollmentNoteOwners.defaultsKey
        )

        #expect(EnrollmentNoteOwners.apply(using: context, defaults: defaults) == 2)

        #expect(wholeClass.scope == .student(child))
        #expect(wholeClass.searchIndexStudentID == child)
        #expect(!wholeClass.scopeIsAll)
        #expect(nobody.scope == .student(child))
        #expect(namesClassmate.scope == .student(classmate))
        #expect(namesTwo.scope == .students(two))
        #expect(notWaiting.scope == .all)
        // It never saves, and keeps the list until the pass that saved forgets it.
        #expect(context.hasChanges)
        #expect(EnrollmentNoteOwners.isPending(defaults: defaults))
        EnrollmentNoteOwners.forget(defaults: defaults)
        #expect(!EnrollmentNoteOwners.isPending(defaults: defaults))
    }

    @Test("A deleted note, an id that isn't a note and a value that isn't an id change nothing")
    func applyPassesOverWhatItCannotUse() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()
        let deleted = try note(.all, in: context)
        let badChild = try note(.all, in: context)
        #expect(CoreDataTestHelpers.save(context))
        context.delete(deleted)
        defaults.set([
            try #require(deleted.id).uuidString: child.uuidString,
            try #require(badChild.id).uuidString: "not-an-id",
            UUID().uuidString: child.uuidString,
            "not-an-id": child.uuidString
        ], forKey: EnrollmentNoteOwners.defaultsKey)

        #expect(EnrollmentNoteOwners.apply(using: context, defaults: defaults) == 0)
        #expect(badChild.scope == .all)
    }

    @Test("With nothing waiting the launch step touches nothing")
    func applyWithNothingWaiting() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()
        let wholeClass = try note(.all, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(!EnrollmentNoteOwners.isPending(defaults: defaults))
        #expect(EnrollmentNoteOwners.apply(using: context, defaults: defaults) == 0)
        #expect(!context.hasChanges)
        #expect(wholeClass.scope == .all)
    }

    // MARK: - Before the store loads

    @Test("The file is read for each note's child, a 16-byte id or text in any case")
    func readFindsEachNotesChild() throws {
        let url = try Self.makeFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let enrollment = UUID(), otherEnrollment = UUID()
        let onEnrollment = UUID(), lowercased = UUID(), onOther = UUID(), onGone = UUID(), onNone = UUID()
        try Self.execute(at: url, [
            "CREATE TABLE ZSTUDENTTRACKENROLLMENT (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZSTUDENTID VARCHAR)",
            "CREATE TABLE ZNOTE (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZSTUDENTTRACKENROLLMENTID VARCHAR)",
            "INSERT INTO ZSTUDENTTRACKENROLLMENT (ZID, ZSTUDENTID) VALUES "
                + "(\(Self.blob(enrollment)), '\(child.uuidString)'), "
                + "(\(Self.blob(otherEnrollment)), '\(classmate.uuidString.lowercased())'), "
                + "(\(Self.blob(UUID())), '')",
            "INSERT INTO ZNOTE (ZID, ZSTUDENTTRACKENROLLMENTID) VALUES "
                + "(\(Self.blob(onEnrollment)), '\(enrollment.uuidString)'), "
                + "(\(Self.blob(lowercased)), '\(enrollment.uuidString.lowercased())'), "
                + "(\(Self.blob(onOther)), '\(otherEnrollment.uuidString)'), "
                + "(\(Self.blob(onGone)), '\(UUID().uuidString)'), "
                + "(\(Self.blob(onNone)), NULL), "
                + "(\(Self.blob(UUID())), '')"
        ])

        #expect(EnrollmentNoteOwners.read(storeURL: url) == [
            onEnrollment: child, lowercased: child, onOther: classmate
        ])
    }

    @Test("A file without the enrollments or the note column, or no file, reads as nothing")
    func readNeedsTheOldTables() throws {
        let url = try Self.makeFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Self.execute(at: url, [
            "CREATE TABLE ZSTUDENTTRACKENROLLMENT (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZSTUDENTID VARCHAR)",
            "CREATE TABLE ZNOTE (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZBODY VARCHAR)",
            "INSERT INTO ZSTUDENTTRACKENROLLMENT (ZID, ZSTUDENTID) VALUES "
                + "(\(Self.blob(UUID())), '\(child.uuidString)')"
        ])
        #expect(EnrollmentNoteOwners.read(storeURL: url).isEmpty)
        let missing = url.deletingLastPathComponent().appendingPathComponent("none.sqlite")
        #expect(EnrollmentNoteOwners.read(storeURL: missing).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing.path), "reading made a file")
    }

    @Test("What a second store adds joins the list already waiting")
    func stashMergesIntoTheList() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let url = try Self.makeFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let enrollment = UUID(), earlier = UUID(), later = UUID()
        try Self.execute(at: url, [
            "CREATE TABLE ZSTUDENTTRACKENROLLMENT (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZSTUDENTID VARCHAR)",
            "CREATE TABLE ZNOTE (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZSTUDENTTRACKENROLLMENTID VARCHAR)",
            "INSERT INTO ZSTUDENTTRACKENROLLMENT (ZID, ZSTUDENTID) VALUES "
                + "(\(Self.blob(enrollment)), '\(child.uuidString)')",
            "INSERT INTO ZNOTE (ZID, ZSTUDENTTRACKENROLLMENTID) VALUES "
                + "(\(Self.blob(later)), '\(enrollment.uuidString)')"
        ])
        defaults.set([earlier.uuidString: classmate.uuidString], forKey: EnrollmentNoteOwners.defaultsKey)

        EnrollmentNoteOwners.stashOwners(readingStoreAt: url, defaults: defaults)

        let waiting = defaults.dictionary(forKey: EnrollmentNoteOwners.defaultsKey) as? [String: String]
        #expect(waiting == [earlier.uuidString: classmate.uuidString, later.uuidString: child.uuidString])
    }

    // MARK: - SQLite

    /// A path for a new SQLite file in a folder of its own.
    private static func makeFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnrollmentNoteOwners-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("private.sqlite")
    }

    private struct SQLiteFailed: Error {
        let statement: String
    }

    private static func execute(at url: URL, _ statements: [String]) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw SQLiteFailed(statement: "open")
        }
        defer { sqlite3_close(handle) }
        for statement in statements where sqlite3_exec(handle, statement, nil, nil, nil) != SQLITE_OK {
            throw SQLiteFailed(statement: statement)
        }
    }

    /// `id` as Core Data writes a `UUID` attribute: a 16-byte blob literal.
    private static func blob(_ id: UUID) -> String {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return "X'" + bytes.map { String(format: "%02X", $0) }.joined() + "'"
    }
}
