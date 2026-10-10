import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A plan discarded because its last child got the lesson elsewhere keeps the
/// notes written on it: they move to the presentation that gave the lesson
/// (2026-10-10 hunt, a hand-off from the presentation-merge fixes).
@Suite("Year Plan — Releasing Keeps the Plan's Notes")
@MainActor
struct YearPlanReleaseNotesTests {

    @Test("a discarded plan's notes move to the presentation that was given")
    func discardedPlanNotesMove() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game: Static Addition")
        let girl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Baila", lastName: "Glauber")

        let thursday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [girl], scheduledFor: Date().addingTimeInterval(3 * 86_400),
            context: context
        )
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = girl.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = Date().addingTimeInterval(3 * 86_400)
        entry.sequenceGroupKey = "Math::Preliminary"
        entry.statusRaw = YearPlanEntryStatus.promoted.rawValue
        entry.promotedAssignmentID = thursday.id?.uuidString

        let note = CDNote(context: context)
        note.body = "Bring the small bead frame too."
        note.lessonAssignment = thursday

        let today = PresentationFactory.makeDraft(lesson: lesson, students: [girl], context: context)
        CoreDataTestHelpers.save(context)

        let given = try LifecycleService.recordPresentation(
            from: today, presentedAt: Date(), modelContext: context
        )
        CoreDataTestHelpers.save(context)

        #expect(thursday.isDeleted || thursday.managedObjectContext == nil)
        #expect(note.isDeleted == false)
        #expect(note.lessonAssignment?.objectID == given.objectID)
    }
}
