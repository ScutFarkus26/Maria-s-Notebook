import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, #1 and #3.
//
// #1: the same-name lesson merge runs right after the id pass, which leaves
// two copies of one id alone while a Replace restore may still be arriving
// (`DedupSyncState.tieStillSettling`). The name merge then folded those same
// copies anyway, keeping the outgoing record; and with one id on both sides,
// `repointLessonReferences(from: id, to: id)` deleted what pointed at the
// lesson (its track steps, until schema 23 retired them). A group holding two
// copies of one id now belongs to the id pass, a group waits while the
// settling guard says so, and repointing a lesson onto itself changes nothing.
//
// #3: the merge also moves Going Out curriculum links and story match reasons.

@Suite("Lesson name merges (bug hunt 10-12)")
@MainActor
struct LessonMergeFix1012LTests {

    private let now = Date()

    // MARK: - Helpers

    private func lessons(in context: NSManagedObjectContext) -> [CDLesson] {
        context.safeFetch(CDFetchRequest(CDLesson.self)).filter { !$0.isDeleted }
    }

    private func marks(in context: NSManagedObjectContext) -> [CDLessonPresentation] {
        context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).filter { !$0.isDeleted }
    }

    @discardableResult
    private func seedLesson(
        _ name: String, order: Int64 = 0, id: UUID? = nil, in context: NSManagedObjectContext
    ) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: "Geometry", sequence: "Area")
        lesson.orderInSequence = order
        if let id { lesson.id = id }
        return lesson
    }

    /// A child's mark for the lesson, which a merge must keep pointing at it.
    private func seedMark(lesson lessonID: UUID, in context: NSManagedObjectContext) {
        let mark = CDLessonPresentation(context: context)
        mark.lessonID = lessonID.uuidString
        mark.studentID = UUID().uuidString
    }

    /// Runs `body` as a synced device sees its rows: every row has a record in
    /// iCloud except those in `unsent`; each record last changed there at
    /// `changed`, or at its own date for the rows in `lately`; and the last
    /// import into the store began at `lastImport`.
    private func synced<T>(
        unsent: Set<NSManagedObjectID> = [],
        changed: Date,
        lately: [NSManagedObjectID: Date] = [:],
        lastImport: Date?,
        _ body: () -> T
    ) -> T {
        let names: @Sendable (NSManagedObjectID) -> String? = { objectID in
            unsent.contains(objectID) ? nil : "record-\(objectID.uriRepresentation().absoluteString)"
        }
        let changedAt: @Sendable (NSManagedObjectID) -> Date? = { lately[$0] ?? changed }
        let imported: @Sendable (String) -> Date? = { _ in lastImport }
        return DedupSyncState.$recordNameOverride.withValue(names) {
            DedupSyncState.$recordChangedOverride.withValue(changedAt) {
                DedupSyncState.$lastImportOverride.withValue(imported) {
                    body()
                }
            }
        }
    }

    /// Mid-way through a Replace restore on another device: a copy came up a minute ago.
    private func duringRestore<T>(_ body: () -> T) -> T {
        let restoredAt = now.addingTimeInterval(-60)
        return synced(changed: restoredAt, lastImport: now, body)
    }

    // MARK: - #1 Same-id copies belong to the id pass

    @Test("A lesson restored on another device, its old copy not yet gone, keeps both copies and every mark")
    func sameIDLessonPairDuringRestoreKeepsSteps() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        seedLesson("Rectangle", id: id, in: context)
        seedLesson("Rectangle", id: id, in: context)
        seedMark(lesson: id, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let results = duringRestore { DataCleanupService.deduplicateAllModels(using: context) }
        #expect(CoreDataTestHelpers.save(context))

        #expect(results["Lesson"] == nil)
        #expect(results["Lesson (same name)"] == nil)
        #expect(lessons(in: context).count == 2)
        #expect(marks(in: context).map(\.lessonID) == [id.uuidString])
    }

    @Test("The name merge leaves a group with two copies of one id to the id pass, even beside a third lesson")
    func nameMergeSkipsGroupsHoldingOneIDTwice() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        seedLesson("Rectangle", order: 0, id: id, in: context)
        seedLesson("Rectangle", order: 0, id: id, in: context)
        seedLesson("Rectangle", order: 5, in: context)
        seedMark(lesson: id, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.mergeSameNameLessons(using: context) == 0)
        #expect(CoreDataTestHelpers.save(context))
        #expect(lessons(in: context).count == 3)
        #expect(marks(in: context).map(\.lessonID) == [id.uuidString])
    }

    @Test("Repointing a lesson onto its own id changes nothing")
    func repointOntoItselfChangesNothing() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        seedLesson("Rectangle", id: id, in: context)
        let studentID = UUID().uuidString
        for _ in 0..<2 {
            let entry = CDYearPlanEntry(context: context)
            entry.lessonID = id.uuidString
            entry.studentID = studentID
            entry.status = .planned
            let mark = CDLessonPresentation(context: context)
            mark.lessonID = id.uuidString
            mark.studentID = studentID
        }
        #expect(CoreDataTestHelpers.save(context))

        DataCleanupService.repointLessonReferences(from: id, to: id, in: context)

        #expect(!context.hasChanges)
        #expect(context.safeFetch(CDFetchRequest(CDYearPlanEntry.self)).count == 2)
        #expect(context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).count == 2)
    }

    // MARK: - #1 The settling guard covers the whole group

    @Test("Two lessons by one name wait while one isn't in iCloud or changed there lately, and fold once settled")
    func sameNameLessonsWaitForTheGroupToSettle() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let older = seedLesson("Parallelogram", order: 1, in: context)
        let newer = seedLesson("Parallelogram", order: 6, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let olderObject = older.objectID
        let newerObject = newer.objectID
        let longAgo = now.addingTimeInterval(-3600)
        let lately = now.addingTimeInterval(-60)

        // The newer one hasn't gone up yet.
        let unsentPass = synced(unsent: [newerObject], changed: longAgo, lastImport: now) {
            DataCleanupService.mergeSameNameLessons(using: context)
        }
        #expect(unsentPass == 0)

        // Both are up, but the newer one changed in iCloud a minute ago.
        let recentPass = synced(changed: longAgo, lately: [newerObject: lately], lastImport: now) {
            DataCleanupService.mergeSameNameLessons(using: context)
        }
        #expect(recentPass == 0)

        // Nothing has finished importing since that change.
        let noImportPass = synced(changed: longAgo, lastImport: longAgo.addingTimeInterval(-60)) {
            DataCleanupService.mergeSameNameLessons(using: context)
        }
        #expect(noImportPass == 0)
        #expect(lessons(in: context).count == 2)

        // Settled: the older record is kept.
        let settledPass = synced(changed: longAgo, lastImport: now.addingTimeInterval(-1800)) {
            DataCleanupService.mergeSameNameLessons(using: context)
        }
        #expect(settledPass == 1)
        #expect(lessons(in: context).map(\.objectID) == [olderObject])
    }

    // MARK: - #3 Going Out links and story reasons

    @Test("The merge moves Going Out curriculum links and story match reasons onto the kept lesson")
    func mergeRepointsGoingOutAndStoryReasons() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let older = seedLesson("Parallelogram", order: 1, in: context)
        let newer = seedLesson("Parallelogram", order: 6, in: context)
        let other = seedLesson("Rhombus", order: 2, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let olderID = try #require(older.id).uuidString
        let newerID = try #require(newer.id).uuidString
        let otherID = try #require(other.id).uuidString

        let trip = CDGoingOut(context: context)
        trip.title = "Museum of geometry"
        trip.curriculumLinkIDs = "\(newerID),\(otherID)"
        let bothLinked = CDGoingOut(context: context)
        bothLinked.title = "Architecture walk"
        bothLinked.curriculumLinkIDs = "\(olderID),\(newerID)"

        let story = CDStory(context: context)
        story.title = "The Tangram"
        story.relatedLessonIDsRaw = "\(newerID),\(otherID)"
        story.relatedLessonReasonsJSON = try json([newerID: "Cutting shapes apart", otherID: "Four equal sides"])
        let bothMatched = CDStory(context: context)
        bothMatched.title = "Grandfather Tang"
        bothMatched.relatedLessonIDsRaw = "\(olderID),\(newerID)"
        bothMatched.relatedLessonReasonsJSON = try json([olderID: "Base and height", newerID: "Rearranging"])
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.mergeSameNameLessons(using: context) == 1)
        #expect(CoreDataTestHelpers.save(context))

        #expect(trip.curriculumLinkIDs == "\(olderID),\(otherID)")
        #expect(bothLinked.curriculumLinkIDs == olderID)
        #expect(story.relatedLessonReasons == [olderID: "Cutting shapes apart", otherID: "Four equal sides"])
        #expect(bothMatched.relatedLessonReasons == [olderID: "Base and height"])
    }

    private func json(_ reasons: [String: String]) throws -> String {
        try #require(String(data: JSONEncoder().encode(reasons), encoding: .utf8))
    }
}
