//
//  EnrollmentNoteOwners.swift
//  Cosmic Daybook
//
//  Notes that hung on a track enrollment become notes on its child (schema 23).
//
//  Before the Phase 1 build of "Retire the track entities", a quick note could
//  hang on a child's track enrollment (`Note.studentTrackEnrollmentID`).
//  Schema 23 drops the enrollments and that column, so a note whose own scope
//  named no child would have turned into a whole-class note. Its child is the
//  enrollment's `studentID` (`docs/Plans/Plan - Retire the track entities.md`,
//  Decisions).
//
//  The column is gone from the model and the enrollments from the private
//  store, so Core Data can't read them any more. Two halves, one on each side
//  of the migration:
//  - Before the private store migrates, `CoreDataStack.prepareStoresForLoad`
//    reads note → child straight from the SQLite file, read-only, and keeps
//    the list in UserDefaults (`stashOwners(readingStoreAt:)`). It reads only
//    while the file still has the column, so a migrated store reads nothing.
//  - After the store loads, the launch pass (`MigrationRunner.launchSweep`)
//    narrows each listed note that still names no child to that child,
//    through Core Data so the change syncs (`apply(using:)`), and forgets the
//    list once that pass has saved (`forget()`). A note that names a child
//    already keeps its scope.
//
//  The list outlives a launch that migrates and then stops before the pass
//  saves; the next launch applies it.
//

import CoreData
import Foundation
import OSLog
import SQLite3

nonisolated enum EnrollmentNoteOwners {
    private static let logger = Logger.migration

    /// Note id → child id, both `UUID.uuidString`, waiting for the launch pass.
    static let defaultsKey = "EnrollmentNoteOwners.pending"

    // MARK: - Before the store loads

    /// Reads who each enrollment note belongs to from the store at `storeURL`
    /// and adds it to the waiting list. Does nothing for a store without the
    /// enrollment table or the note column (a migrated or a new store).
    static func stashOwners(readingStoreAt storeURL: URL, defaults: UserDefaults = .standard) {
        let owners = read(storeURL: storeURL)
        guard !owners.isEmpty else { return }
        var pending = pendingOwners(defaults: defaults)
        for (note, student) in owners {
            pending[note.uuidString] = student.uuidString
        }
        defaults.set(pending, forKey: defaultsKey)
        logger.notice("Kept the child of \(owners.count, privacy: .public) note(s) on a track enrollment")
    }

    /// Note id → the child of the enrollment it names, read from the SQLite
    /// file, read-only. Empty when the file has no enrollment table or no
    /// enrollment column on notes, or can't be opened.
    static func read(storeURL: URL) -> [UUID: UUID] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [:] }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else {
            if handle != nil { sqlite3_close(handle) }
            return [:]
        }
        defer { sqlite3_close(handle) }
        guard columns(of: "ZSTUDENTTRACKENROLLMENT", in: handle).isSuperset(of: ["ZID", "ZSTUDENTID"]),
              columns(of: "ZNOTE", in: handle).isSuperset(of: ["ZID", "ZSTUDENTTRACKENROLLMENTID"]) else {
            return [:]
        }

        var children: [UUID: UUID] = [:]
        rows("SELECT ZID, ZSTUDENTID FROM ZSTUDENTTRACKENROLLMENT", in: handle) { statement in
            guard let enrollment = uuid(statement, 0), let child = uuid(statement, 1) else { return }
            children[enrollment] = child
        }
        guard !children.isEmpty else { return [:] }

        var owners: [UUID: UUID] = [:]
        let notes = "SELECT ZID, ZSTUDENTTRACKENROLLMENTID FROM ZNOTE "
            + "WHERE ZSTUDENTTRACKENROLLMENTID IS NOT NULL AND ZSTUDENTTRACKENROLLMENTID != ''"
        rows(notes, in: handle) { statement in
            guard let note = uuid(statement, 0), let enrollment = uuid(statement, 1),
                  let child = children[enrollment] else { return }
            owners[note] = child
        }
        return owners
    }

    // MARK: - After the store loads

    /// Whether a list is waiting.
    static func isPending(defaults: UserDefaults = .standard) -> Bool {
        !pendingOwners(defaults: defaults).isEmpty
    }

    /// Narrows each waiting note that names no child to its enrollment's
    /// child, with the student links that go with it. Returns how many
    /// changed. Never saves, and keeps the list: `forget()` once saved.
    @discardableResult
    static func apply(using context: NSManagedObjectContext, defaults: UserDefaults = .standard) -> Int {
        let pending = pendingOwners(defaults: defaults)
        guard !pending.isEmpty else { return 0 }
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "id IN %@", pending.keys.compactMap { UUID(uuidString: $0) })
        var changed = 0
        for note in context.safeFetch(request) where !note.isDeleted {
            guard let id = note.id?.uuidString, let child = pending[id].flatMap({ UUID(uuidString: $0) }),
                  namesNoChild(note.scope) else { continue }
            note.scope = .student(child)
            note.syncStudentLinks(in: context)
            changed += 1
        }
        if changed > 0 {
            logger.notice("Moved \(changed, privacy: .public) note(s) from a track enrollment onto its child")
        }
        return changed
    }

    /// Drops the waiting list, once the pass that applied it has saved.
    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    // MARK: - Pieces

    private static func pendingOwners(defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    /// The whole class, or a list of no one.
    private static func namesNoChild(_ scope: NoteScope) -> Bool {
        switch scope {
        case .all: return true
        case .student: return false
        case .students(let ids): return ids.isEmpty
        }
    }

    /// The column names of `table`, empty when there is no such table.
    private static func columns(of table: String, in handle: OpaquePointer) -> Set<String> {
        var names = Set<String>()
        rows("PRAGMA table_info(\(table))", in: handle) { statement in
            if let name = sqlite3_column_text(statement, 1) { names.insert(String(cString: name)) }
        }
        return names
    }

    private static func rows(_ sql: String, in handle: OpaquePointer, _ body: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            body(statement)
        }
    }

    /// A UUID column: Core Data writes `UUID` attributes as 16 bytes, and the
    /// string foreign keys as `uuidString` text (any case).
    private static func uuid(_ statement: OpaquePointer, _ column: Int32) -> UUID? {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_BLOB:
            guard sqlite3_column_bytes(statement, column) == 16,
                  let bytes = sqlite3_column_blob(statement, column) else { return nil }
            return Data(bytes: bytes, count: 16).withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, column) else { return nil }
            return UUID(uuidString: String(cString: text).trimmingCharacters(in: .whitespaces))
        default:
            return nil
        }
    }
}
