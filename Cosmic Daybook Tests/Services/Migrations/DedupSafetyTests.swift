import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-05 (#20, #62): when the cleanup can't tell which copy every
// device will keep, it deletes nothing, and a cleanup whose save failed takes
// its half-done changes back instead of leaving them for the next save.

@Suite("Dedup safety")
@MainActor
struct DedupSafetyTests {

    private func twinStudents(in context: NSManagedObjectContext) {
        let id = UUID()
        for _ in 0..<2 {
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern").id = id
        }
    }

    // MARK: - Sync off (#20)

    @Test("With iCloud sync off, the cleanup deletes nothing")
    func syncOffDeletesNothing() throws {
        // CloudKit is off for the test stack, as on a device with sync off:
        // no copy has a record, so no device-independent keeper exists.
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        twinStudents(in: context)
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(using: context, container: stack.container)

        #expect(results.isEmpty)
        #expect(context.safeFetch(CDFetchRequest(CDStudent.self)).count == 2)
    }

    @Test("In a synced notebook, copies none of which is in iCloud yet are left for later")
    func unsentCopiesWait() throws {
        let context = try CoreDataTestHelpers.makeContext()
        twinStudents(in: context)
        #expect(CoreDataTestHelpers.save(context))

        let noneSent: @Sendable (NSManagedObjectID) -> String? = { _ in nil }
        let waited = DedupSyncState.$syncsOverride.withValue(true) {
            DedupSyncState.$recordNameOverride.withValue(noneSent) {
                DataCleanupService.deduplicateAllModels(using: context)
            }
        }
        #expect(waited.isEmpty)
        #expect(context.safeFetch(CDFetchRequest(CDStudent.self)).count == 2)

        // Students have no creation time, so the record name picks the keeper: with one copy
        // still unsent the group keeps waiting (2026-10-05 sync hunt, the Replace-restore tie).
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        let sent = try #require(students.first).objectID
        let oneSent: @Sendable (NSManagedObjectID) -> String? = { $0 == sent ? "A-record" : nil }
        let stillWaiting = DedupSyncState.$syncsOverride.withValue(true) {
            DedupSyncState.$recordNameOverride.withValue(oneSent) {
                DataCleanupService.deduplicateAllModels(using: context)
            }
        }
        #expect(stillWaiting.isEmpty)
        #expect(context.safeFetch(CDFetchRequest(CDStudent.self)).count == 2)

        // Once both have gone up, the next pass folds them onto the lower record name.
        let bothSent: @Sendable (NSManagedObjectID) -> String? = { $0 == sent ? "A-record" : "B-record" }
        let folded = DedupSyncState.$syncsOverride.withValue(true) {
            DedupSyncState.$recordNameOverride.withValue(bothSent) {
                DataCleanupService.deduplicateAllModels(using: context)
            }
        }
        #expect(folded == ["Student": 1])
        #expect(context.safeFetch(CDFetchRequest(CDStudent.self)).map(\.objectID) == [sent])
    }

    // MARK: - A tie mid-way through a Replace restore (2026-10-05 sync hunt)

    private func twinNotes(
        in context: NSManagedObjectContext, createdAt: (Date, Date)
    ) throws -> (first: NSManagedObjectID, second: NSManagedObjectID) {
        let id = UUID()
        let first = CoreDataTestHelpers.seedNote(in: context, body: "Traced the sandpaper letters")
        let second = CoreDataTestHelpers.seedNote(in: context, body: "Traced the sandpaper letters")
        first.id = id
        second.id = id
        first.createdAt = createdAt.0
        second.createdAt = createdAt.1
        #expect(CoreDataTestHelpers.save(context))
        return (first.objectID, second.objectID)
    }

    private func notesLeft(in context: NSManagedObjectContext) -> [NSManagedObjectID] {
        context.safeFetch(CDFetchRequest(CDNote.self)).map(\.objectID)
    }

    @Test("Tied copies wait while one changed in iCloud lately, and fold once an import after it has finished")
    func tiedCopiesWaitForTheRestoreToSettle() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let (first, second) = try twinNotes(in: context, createdAt: (created, created))
        let now = Date()
        let names: @Sendable (NSManagedObjectID) -> String? = { $0 == first ? "A-record" : "B-record" }

        func pass(changed: Date, lastImport: Date?) -> Int {
            let changedAt: @Sendable (NSManagedObjectID) -> Date? = { $0 == second ? changed : created }
            let imported: @Sendable (String) -> Date? = { _ in lastImport }
            return DedupSyncState.$recordNameOverride.withValue(names) {
                DedupSyncState.$recordChangedOverride.withValue(changedAt) {
                    DedupSyncState.$lastImportOverride.withValue(imported) {
                        DataCleanupService.deduplicate(CDNote.self, using: context)
                    }
                }
            }
        }

        // The restored copy came up a minute ago.
        #expect(pass(changed: now.addingTimeInterval(-60), lastImport: now) == 0)
        // An hour ago, but no import that began after it has finished here.
        #expect(pass(changed: now.addingTimeInterval(-3600), lastImport: now.addingTimeInterval(-7200)) == 0)
        #expect(pass(changed: now.addingTimeInterval(-3600), lastImport: nil) == 0)
        #expect(notesLeft(in: context).count == 2)

        // Settled: the keeper is the lower record name, as on every device.
        #expect(pass(changed: now.addingTimeInterval(-3600), lastImport: now.addingTimeInterval(-1800)) == 1)
        #expect(notesLeft(in: context) == [first])
    }

    @Test("Copies with different creation times fold at once, even mid-restore")
    func untiedCopiesDoNotWait() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let (first, second) = try twinNotes(in: context, createdAt: (created.addingTimeInterval(5), created))
        let now = Date()
        // The later copy is the one in iCloud, and it changed a moment ago: neither matters,
        // since the earlier creation time decides the keeper the same way everywhere.
        let names: @Sendable (NSManagedObjectID) -> String? = { $0 == first ? "A-record" : nil }
        let changedAt: @Sendable (NSManagedObjectID) -> Date? = { _ in now }
        let removed = DedupSyncState.$recordNameOverride.withValue(names) {
            DedupSyncState.$recordChangedOverride.withValue(changedAt) {
                DataCleanupService.deduplicate(CDNote.self, using: context)
            }
        }
        #expect(removed == 1)
        #expect(notesLeft(in: context) == [second])
    }

    // MARK: - A failed save (#62)

    @Test("A cleanup whose save fails rolls its changes back and reports nothing removed")
    func failedSaveRollsBack() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        for _ in 0..<2 {
            CoreDataTestHelpers.seedNote(in: context, body: "Counted to 100 with the chain").id = id
        }
        #expect(CoreDataTestHelpers.save(context))
        // An unsaveable row beside the pass: a required field left empty makes
        // the save fail.
        CoreDataTestHelpers.seedNote(in: context).setValue(nil, forKey: "body")

        #expect(DataCleanupService.deduplicateNotesStrong(using: context) == 0)

        #expect(!context.hasChanges)
        let notes = context.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { $0.id == id })
    }
}
