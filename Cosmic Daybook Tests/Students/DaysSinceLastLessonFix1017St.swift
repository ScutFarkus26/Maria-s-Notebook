import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #44: the record's "School Days Since Last Lesson"
/// and the roster's lesson age read a child's last lesson by different
/// rules, so the two could disagree about one child. Both now read it the
/// roster's way: given presentations of the last year, Parsha lessons aside
/// however their area was typed.
@Suite("Last lesson, record and roster (fix 10-17 St)")
@MainActor
struct DaysSinceLastLessonFix1017StTests {

    @Test("The record and the roster agree on a child's last lesson")
    func recordMatchesRoster() throws {
        let context = try CoreDataTestHelpers.makeContext()
        SchoolCalendarService.shared.invalidateCache()
        let today = AppCalendar.startOfDay(Date())
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let math = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Math", sequence: "Decimal"
        )
        // Typed with padding: the roster has always left it out.
        let parsha = CoreDataTestHelpers.seedLesson(in: context, name: "Noach", area: " Parsha ", sequence: "Noach")
        let mathDay = AppCalendar.addingDays(-20, to: today)
        _ = PresentationFactory.makePresented(
            lesson: math, students: [maya], presentedAt: mathDay, createdAt: mathDay, context: context
        )
        _ = PresentationFactory.makePresented(lesson: parsha, students: [maya], presentedAt: today, context: context)
        #expect(CoreDataTestHelpers.save(context))
        let mayaID = try #require(maya.id)

        #expect(DaysSinceLastLessonView.lastLessonDate(studentID: mayaID, in: context) == mathDay)
        let roster = StudentsViewModel().computeDaysSinceLastLessonCache(
            for: [maya], using: context, calendar: AppCalendar.shared
        )
        let record = LessonAgeHelper.schoolDaysSinceCreation(createdAt: mathDay, asOf: Date(), using: context)
        #expect(roster[mayaID] == record)
    }

    @Test("A child never given a lesson has none on the record either")
    func neverGivenHasNone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let noa = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "C")
        #expect(CoreDataTestHelpers.save(context))
        #expect(DaysSinceLastLessonView.lastLessonDate(studentID: try #require(noa.id), in: context) == nil)
    }
}
