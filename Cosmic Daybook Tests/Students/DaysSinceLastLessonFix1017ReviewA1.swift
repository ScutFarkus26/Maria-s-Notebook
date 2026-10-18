import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17 review (a1), #3: the last-lesson window read
/// `createdAt` while dating each lesson by `presentedAt`, so a lesson
/// drafted over a year ago and given this week counted nowhere. The window
/// now reads the presentation date, falling back to `createdAt` without one,
/// and Today's window floor reads the same field.
@Suite("Last lesson windows on the presentation date (Fix1017ReviewA1)")
@MainActor
struct DaysSinceLastLessonFix1017ReviewA1Tests {

    @Test("A lesson drafted over a year ago and given this week is her last lesson")
    func oldDraftGivenRecently() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let today = AppCalendar.startOfDay(Date())
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let math = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Math", sequence: "Decimal"
        )
        let drafted = AppCalendar.addingDays(-400, to: today)
        let given = AppCalendar.addingDays(-4, to: today)
        _ = PresentationFactory.makePresented(
            lesson: math, students: [maya], presentedAt: given, createdAt: drafted, context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        let mayaID = try #require(maya.id)

        #expect(DaysSinceLastLessonView.lastLessonDate(studentID: mayaID, in: context) == given)
        #expect(StudentsViewModel.lastLessonDates(in: context, calendar: AppCalendar.shared)[mayaID] == given)
    }

    @Test("A lesson given over a year ago, though created this week, is outside the window")
    func recentRowGivenLongAgo() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let today = AppCalendar.startOfDay(Date())
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let math = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Math", sequence: "Decimal"
        )
        _ = PresentationFactory.makePresented(
            lesson: math, students: [maya],
            presentedAt: AppCalendar.addingDays(-400, to: today), createdAt: today, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        #expect(DaysSinceLastLessonView.lastLessonDate(studentID: try #require(maya.id), in: context) == nil)
    }

    @Test("Today's window floor is the oldest presentation date in the window")
    func floorReadsPresentationDate() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let now = Date()
        let today = AppCalendar.startOfDay(now)
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let math = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Math", sequence: "Decimal"
        )
        let given = AppCalendar.addingDays(-4, to: today)
        _ = PresentationFactory.makePresented(
            lesson: math, students: [maya], presentedAt: given,
            createdAt: AppCalendar.addingDays(-400, to: today), context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let floor = TodayViewModel.presentedWindowFloor(calendar: AppCalendar.shared, now: now, in: context)
        #expect(floor == given)
    }
}
