import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Putting a presentation on a day promotes each child's planned year-plan entry for
/// that lesson and moves it to the day, and lays nothing on the lessons after. Until
/// 2026-11-03 it wrote an entry on every later lesson of the sequence, which dressed
/// whole strands Planned on the Checklist.
@Suite("Year plan — promotion on scheduling")
@MainActor
struct YearPlanPromotionOnScheduleTests {

    @Test("scheduling promotes her entry for the lesson, moves it to the day, and plans nothing after it")
    func schedulingPromotesOnlyThisLesson() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let bruno = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bruno", lastName: "Test")
        let first = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Position of Two Lines", area: "Geometry", sequence: "Lines"
        )
        first.orderInSequence = 0
        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Parallel Lines", area: "Geometry", sequence: "Lines"
        )
        second.orderInSequence = 1
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(ada.id).uuidString
        entry.lessonID = try #require(first.id).uuidString
        entry.plannedDate = try CoreDataTestHelpers.day("2026-11-20")
        let assignment = PresentationFactory.makeDraft(lesson: first, students: [ada, bruno], context: context)
        let day = try CoreDataTestHelpers.day("2026-11-10")
        assignment.schedule(for: day)
        try context.save()

        PresentationDropHandling.promoteYearPlanEntries(for: assignment, fallbackDate: { day }, context: context)

        // Ada's entry followed the presentation; Bruno, who had none, got none; and
        // neither child has an entry on Parallel Lines.
        let entries = context.safeFetch(CDFetchRequest(CDYearPlanEntry.self))
        #expect(entries.count == 1)
        #expect(entry.status == .promoted)
        #expect(entry.promotedAssignmentID == assignment.id?.uuidString)
        #expect(entry.plannedDate == day)
    }

    @Test("a draft still in the Inbox promotes nothing")
    func inboxDraftLeavesTheEntry() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Lines", area: "Geometry", sequence: "Lines")
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(ada.id).uuidString
        entry.lessonID = try #require(lesson.id).uuidString
        entry.plannedDate = try CoreDataTestHelpers.day("2026-11-20")
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [ada], context: context)
        try context.save()

        PresentationDropHandling.promoteYearPlanEntries(for: assignment, fallbackDate: { Date() }, context: context)

        #expect(entry.status == .planned)
    }
}
