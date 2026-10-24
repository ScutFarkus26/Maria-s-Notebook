import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Plan - Schedules, Phase 2A: the Schedules page's Week view, moving
/// between days, following saves elsewhere, and the warnings it words.
@Suite("Schedules page: weeks and warnings")
@MainActor
struct SchedulesPageWeekTests {
    private typealias Support = TimetableTestSupport

    private func page(_ context: NSManagedObjectContext, day: Date = Support.monday) -> SchedulesPageModel {
        SchedulesPageTestSupport.page(context, day: day)
    }

    private func setUpPage(_ context: NSManagedObjectContext) throws -> (SchedulesPageModel, [TimetableLaneSnapshot]) {
        try SchedulesPageTestSupport.setUpPage(context)
    }

    // MARK: - Weeks and moving

    @Test("The Week view shows Monday to Friday, a weekday off reads no school, a school Sunday joins")
    func weekDays() throws {
        let context = try Support.context()
        let (model, _) = try setUpPage(context)
        let holiday = CDNonSchoolDay(context: context)
        holiday.date = Support.wednesday
        let sunday = Support.day(2026, 10, 25)
        let override = CDSchoolDayOverride(context: context)
        override.date = sunday
        #expect(CoreDataTestHelpers.save(context))

        model.mode = .week
        #expect(model.week.map(\.day) == [
            sunday, Support.monday, Support.tuesday, Support.wednesday, Support.day(2026, 10, 29), Support.friday
        ])
        #expect(model.week.first { $0.day == Support.wednesday }?.resolved.isSchoolDay == false)
        #expect(model.week.first { $0.day == sunday }?.resolved.isSchoolDay == true)
        model.mode = .day
        #expect(model.week.isEmpty)
    }

    @Test("Back and on step a day, or a week in the Week view; Today comes back to now")
    func moving() throws {
        let context = try Support.context()
        let model = page(context, day: Support.wednesday)
        #expect(!model.isToday)
        model.step(-1)
        #expect(model.day == Support.tuesday)
        model.mode = .week
        model.step(1)
        #expect(model.day == Support.day(2026, 11, 3))
        model.goToToday()
        #expect(model.day == Support.monday)
        #expect(model.isToday)
    }

    // MARK: - Warnings

    @Test("A child with Morah Devora in the same half as one of the guide's lessons is warned about, by name")
    func childWarning() throws {
        let context = try Support.context()
        let (model, lanes) = try setUpPage(context)
        let devora = lanes[3]
        let lucy = CoreDataTestHelpers.seedStudent(in: context, firstName: "Lucy", lastName: "Tal", level: .upper)
        let lucyID = try #require(lucy.id).uuidString
        let lesson = CDLessonAssignment(context: context)
        lesson.lessonID = UUID().uuidString
        lesson.lessonTitleSnapshot = "Long Division"
        lesson.studentIDs = [lucyID]
        lesson.schedule(onDay: Support.monday, using: Support.calendar)
        #expect(model.addBlock(
            TimetableBlockValues(
                startMinute: Support.minutes(9), lengthMinutes: 45, title: "Chumash", studentIDs: [lucyID]
            ),
            laneID: devora.id, on: [.monday]
        ))
        model.studentNames = SchedulesView.names([lucy])

        #expect(model.warningLines.map(\.text) == ["Lucy T is with Morah Devora 9:00–9:45 this morning."])
        let warning = try #require(model.warningLines.first?.warning)
        let row = try #require(ScheduleDayRows.row(holdingLesson: warning.lessonID, in: model.resolved))
        #expect(row.lane.isGuide)
    }

    @Test("A save elsewhere that touches the timetable reloads the page")
    func followsSavesElsewhere() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let model = page(stack.viewContext)
        #expect(model.setUp())
        let before = model.reloadCount
        model.scheduleReload()
        await model.reloadTask?.value
        #expect(model.reloadCount == before + 1)
        #expect(SchedulesPageModel.inputEntities.isSuperset(of: ["TimetableLane", "TimetableBlock", "TimetableChange"]))
    }
}
