import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// "Days since last lesson", computed once (`DaysSinceLastLesson`, Simplify
/// the app, Phase 3). Before, four copies: the roster and Presentations left
/// Parsha lessons out, the record read the roster's, and the lesson planner
/// counted them (in calendar days). Now every screen leaves them out.
@Suite("Days since last lesson, one rule")
@MainActor
struct DaysSinceLastLessonRuleTests {

    @Test("Days since last lesson leaves Parsha lessons out, however the area is typed")
    func parshaLeftOut() throws {
        let mayaID = UUID()
        let math = UUID()
        let parsha = UUID()
        let mathDay = try CoreDataTestHelpers.day("2026-10-01")
        let parshaDay = try CoreDataTestHelpers.day("2026-10-15")
        let rows = [
            DaysSinceLastLesson.Given(lessonID: math, studentIDs: [mayaID], date: mathDay),
            DaysSinceLastLesson.Given(lessonID: parsha, studentIDs: [mayaID], date: parshaDay)
        ]
        let last = DaysSinceLastLesson.lastLessons(from: rows, parshaLessonIDs: [parsha])
        #expect(last[mayaID] == DaysSinceLastLesson.LastLesson(date: mathDay, lessonID: math))

        #expect(DaysSinceLastLesson.isParsha(area: " Parsha ", sequence: "Noach"))
        #expect(DaysSinceLastLesson.isParsha(area: "Judaics", sequence: "PARSHA"))
        #expect(!DaysSinceLastLesson.isParsha(area: "Parsha Stories", sequence: "Bereishit"))
    }

    @Test("Every screen's count skips Parsha: roster, record, Presentations and the planner")
    func everyCopySkipsParsha() throws {
        let context = try CoreDataTestHelpers.makeContext()
        SchoolCalendarService.shared.invalidateCache()
        let today = AppCalendar.startOfDay(Date())
        let mathDay = AppCalendar.addingDays(-20, to: today)
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let math = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Mathematics", sequence: "Decimal"
        )
        let parsha = CoreDataTestHelpers.seedLesson(in: context, name: "Noach", area: " parsha", sequence: "Noach")
        let mathGiven = PresentationFactory.makePresented(
            lesson: math, students: [maya], presentedAt: mathDay, context: context
        )
        let parshaGiven = PresentationFactory.makePresented(
            lesson: parsha, students: [maya], presentedAt: today, context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        let mayaID = try #require(maya.id)
        let expected = DaysSinceLastLesson.schoolDays(since: mathDay, using: context)
        try #require(expected > 0)

        // Roster and record.
        #expect(DaysSinceLastLesson.lastLessons(in: context)[mayaID]?.date == mathDay)
        #expect(DaysSinceLastLessonView.lastLessonDate(studentID: mayaID, in: context) == mathDay)
        let roster = StudentsViewModel().computeDaysSinceLastLessonCache(
            for: [maya], using: context, calendar: AppCalendar.shared
        )
        #expect(roster[mayaID] == expected)

        // Presentations.
        let presentations = PresentationsViewModel()
        presentations.viewContext = context
        presentations.calculateDaysSinceLastLesson(
            lessonAssignments: [mathGiven, parshaGiven], lessons: [math, parsha], students: [maya]
        )
        #expect(presentations.daysSinceLastLessonByStudent[mayaID] == expected)
        #expect(presentations.lastAreaByStudent[mayaID] == "Mathematics")

        // The lesson planner, which used to count Parsha lessons (and calendar days).
        let profile = StudentReadinessAssessor.assessReadiness(for: maya, context: context)
        #expect(profile.daysSinceLastPresentation == expected)
    }

    @Test("An undated 'given earlier' mark doesn't read as taught today on the roster")
    func undatedMarkSkippedOnTheRoster() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Spindle Box", area: "Math", sequence: "Numbers"
        )
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let undated = PresentationFactory.makeDraft(lesson: lesson, students: [maya], context: context)
        undated.markPreviouslyPresented()
        #expect(CoreDataTestHelpers.save(context))

        #expect(DaysSinceLastLesson.lastLessons(in: context)[try #require(maya.id)] == nil)
    }
}
