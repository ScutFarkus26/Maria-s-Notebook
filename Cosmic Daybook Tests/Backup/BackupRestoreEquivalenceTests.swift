import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The restore imports one entity type at a time (2026-09-27): the archive is
// decoded off the main actor as it is read (`BackupImporter.decodeArchive`),
// then each type is moved out of the payload, deduplicated in place, imported
// in dependency order inside one main-actor turn, and freed. Pinned here against
// the restore as it was — every entry read, then the whole payload decoded,
// deduplicated into a second copy and imported, kept verbatim in
// BackupService+LegacyRestore.swift: the same records, summary and progress in
// merge mode (into an empty store, a store already holding every record, one
// holding part of the backup) and in replace mode; with the guide's unsaved
// edits pending, both modes; for an archive with every type ahead of the types
// it links to, and one with rows that do not decode, entries written twice and
// entities this version does not know. Failures, order and threads:
// BackupRestoreTransactionTests.
@Suite("Backup restore against the one-pass restore", .serialized)
@MainActor
struct BackupRestoreEquivalenceTests {
    private typealias Restore = BackupRestoreFixtures
    private typealias Fixtures = BackupStreamingFixtures

    // MARK: - Same records

    @Test("Merge into an empty store: the old records, summary and progress")
    func mergeIntoAnEmptyStore() async throws {
        let (store, url) = try await Restore.makeBackup()
        defer { store.remove() }
        let restored = try await Restore.expectSameRestore(of: url, mode: .merge, "empty store")
        let rows = try Restore.snapshot(of: restored.viewContext)
        #expect(Set(BackupEntityTable.names).isSubset(of: rows.keys), "every backed-up type restored")
        #expect(rows["Note"]?.count == 1_206)
    }

    @Test("Merge into a store already holding every record: updated in place, as before")
    func mergeIntoTheSameRecords() async throws {
        let (store, url) = try await Restore.makeBackup()
        defer { store.remove() }
        let restored = try await Restore.expectSameRestore(of: url, mode: .merge, preparing: { context in
            _ = try await Restore.legacyRestore(url, into: context, mode: .merge)
        }, "same records")
        #expect(try Restore.snapshot(of: restored.viewContext)["Note"]?.count == 1_206)
    }

    @Test("Merge into a store holding part of the backup and records it lacks")
    func mergeIntoAPartlyMatchingStore() async throws {
        let (store, url) = try await Restore.makeBackup()
        defer { store.remove() }
        let payload = try await BackupImporter.decodeArchive(at: url).payload
        let extra = (0..<25).map { _ in UUID() }
        let restored = try await Restore.expectSameRestore(of: url, mode: .merge, preparing: { context in
            Restore.seedOverlap(of: payload, extra: extra, into: context)
            try context.save()
        }, "partly matching store")
        let notes = try Restore.snapshot(of: restored.viewContext)["Note"]
        #expect(notes?.count == 1_206 + 25, "records the backup lacks kept")
    }

    @Test("Replace a store holding part of the backup and records it lacks")
    func replaceAStore() async throws {
        let (store, url) = try await Restore.makeBackup()
        defer { store.remove() }
        let payload = try await BackupImporter.decodeArchive(at: url).payload
        let extra = (0..<25).map { _ in UUID() }
        let restored = try await Restore.expectSameRestore(of: url, mode: .replace, preparing: { context in
            Restore.seedOverlap(of: payload, extra: extra, into: context)
            try context.save()
        }, "replace")
        let notes = try Restore.snapshot(of: restored.viewContext)["Note"]
        #expect(notes?.count == 1_206, "records the backup lacks cleared")
    }

    @Test("Every type ahead of the types it links to: restored as the archive in order was")
    func childrenAheadOfParents() async throws {
        let (store, url) = try await Restore.makeBackup()
        defer { store.remove() }
        let source = try Fixtures.contents(of: url)
        let head = Array(source.paths.prefix(2))
        #expect(head == ["manifest.json", "preferences.json"])
        let paths = head + source.paths.dropFirst(2).reversed()
        let reversed = store.archiveURL("Reversed")
        try Restore.writeArchive(paths.map { ($0, source.bodies[$0] ?? Data()) }, to: reversed)
        for (child, parent) in [("WorkCheckIn", "WorkModel"), ("ScheduleSlot", "Schedule"), ("Note", "Student")] {
            let childAt = try #require(paths.firstIndex(of: Restore.path(child)))
            let parentAt = try #require(paths.firstIndex(of: Restore.path(parent)))
            #expect(childAt < parentAt, "\(child) comes first")
        }

        let old = try CoreDataTestHelpers.makeInMemoryStack()
        let new = try CoreDataTestHelpers.makeInMemoryStack()
        let oldOutcome = try await Restore.legacyRestore(url, into: old.viewContext, mode: .merge)
        let newOutcome = try await Restore.restore(reversed, into: new.viewContext, mode: .merge)
        #expect(newOutcome.progress == oldOutcome.progress)
        #expect(newOutcome.summary.warnings == oldOutcome.summary.warnings)
        #expect(newOutcome.summary.entityCounts == oldOutcome.summary.entityCounts)
        try Restore.expectSameStore(new.viewContext, old.viewContext, "children first")

        // Linked to parents that arrived after them in the archive.
        let links = [
            ("WorkCheckIn", "work"), ("JobAssignment", "job"), ("ScheduleSlot", "schedule"),
            ("IssueAction", "issue"), ("GoingOutChecklistItem", "goingOut")
        ]
        for (entity, relationship) in links {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "%K != nil", relationship)
            #expect(try new.viewContext.count(for: request) >= 1, "\(entity).\(relationship)")
        }
    }

    @Test("Rows that don't decode, entries written twice, unknown entities: the old records and warnings, in order")
    func brokenEntries() async throws {
        let (store, url) = try await Restore.makeBackup()
        defer { store.remove() }
        let source = try Fixtures.contents(of: url)
        let broken = store.archiveURL("Broken")
        try Restore.writeArchive(try Restore.brokenEntries(from: source), to: broken)

        let restored = try await Restore.expectSameRestore(of: broken, mode: .merge, "broken archive")
        let rows = try Restore.snapshot(of: restored.viewContext)
        #expect(rows["Student"] == nil, "a row that does not decode skips its type")
        #expect(rows["Note"]?.count == 1_206, "the first Note entry stands")
        #expect(rows["WorkModel"]?.isEmpty == false, "the second WorkModel entry stands")

        let warnings = try await Restore.restore(broken, into: CoreDataTestHelpers.makeContext(), mode: .merge)
            .summary.warnings
        let prefixes = [
            "Student records could not be read", "Unknown entity 'Mystery'", "Note records could not be read",
            "WorkModel records could not be read", "Unknown entity 'Riddle'"
        ]
        let order = prefixes.compactMap { prefix in warnings.firstIndex { $0.hasPrefix(prefix) } }
        #expect(order.count == prefixes.count && order == order.sorted(), "archive order: \(warnings)")
    }

    @Test("The guide's unsaved edits pending when a restore begins: the old records", arguments: [
        BackupService.RestoreMode.merge, .replace
    ])
    func unsavedEditsPending(mode: BackupService.RestoreMode) async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let studentID = try #require(try await BackupImporter.decodeArchive(at: url).payload.students.first?.id)
        let (keptID, typedID) = (UUID(), UUID())
        _ = try await Restore.expectSameRestore(of: url, mode: mode, preparing: { context in
            // Saved: a student the backup also holds, and a note it lacks.
            let student = NSEntityDescription.insertNewObject(forEntityName: "Student", into: context)
            student.setValue(studentID, forKey: "id")
            student.setValue("Before", forKey: "firstName")
            let kept = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
            kept.setValue(keptID, forKey: "id")
            kept.setValue("Saved; the backup lacks it", forKey: "body")
            try context.save()
            // Not saved when the restore begins: an edit to each, and a new note.
            student.setValue("Edited, not saved", forKey: "firstName")
            kept.setValue("Edited, not saved", forKey: "body")
            let typed = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
            typed.setValue(typedID, forKey: "id")
            typed.setValue("Typed, not saved", forKey: "body")
        }, "\(mode.rawValue) with unsaved edits")
    }
}
