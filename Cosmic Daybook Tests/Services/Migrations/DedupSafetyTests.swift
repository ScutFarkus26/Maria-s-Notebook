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

        // Once one copy has gone up, the next pass folds them.
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        let sent = try #require(students.first).objectID
        let oneSent: @Sendable (NSManagedObjectID) -> String? = { $0 == sent ? "A-record" : nil }
        let folded = DedupSyncState.$syncsOverride.withValue(true) {
            DedupSyncState.$recordNameOverride.withValue(oneSent) {
                DataCleanupService.deduplicateAllModels(using: context)
            }
        }
        #expect(folded == ["Student": 1])
        #expect(context.safeFetch(CDFetchRequest(CDStudent.self)).map(\.objectID) == [sent])
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
