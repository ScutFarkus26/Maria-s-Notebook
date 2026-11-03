import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What the "to check first" lists do with a row (`WorkToShowFirst+Actions`):
/// log it from the present sheet without touching a classmate's part, and put
/// it on today's checks from a strip card without a second check for the day.
@Suite("Work to show first: logging and Check Today")
@MainActor
struct WorkToShowFirstActionTests {

    private struct Fixture {
        let context: NSManagedObjectContext
        let first: CDLesson
        let second: CDLesson
        let ada: CDStudent
        let ben: CDStudent

        var adaID: UUID { ada.id ?? UUID() }
        var benID: UUID { ben.id ?? UUID() }
        var lessons: [CDLesson] { [first, second] }
    }

    private func fixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Addition", area: "Math", sequence: "Addition"
        )
        first.id = UUID()
        first.orderInSequence = 1
        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game Addition", area: "Math", sequence: "Addition"
        )
        second.id = UUID()
        second.orderInSequence = 2
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        ada.id = UUID()
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Moss")
        ben.id = UUID()
        return Fixture(context: context, first: first, second: second, ada: ada, ben: ben)
    }

    @discardableResult
    private func work(for child: UUID, on lesson: CDLesson, in context: NSManagedObjectContext) throws -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: lesson.name, studentID: child, lessonID: try #require(lesson.id)
        )
        work.status = .active
        return work
    }

    /// One row on the first lesson that Ada and Ben share, neither finished.
    private func sharedRow(_ fixture: Fixture) throws -> CDWorkModel {
        let shared = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        shared.title = "Bead chains poster"
        for child in [fixture.adaID, fixture.benID] {
            let participant = CDWorkParticipantEntity(context: fixture.context)
            participant.id = UUID()
            participant.studentID = child.uuidString
            participant.work = shared
        }
        return shared
    }

    private func item(for child: UUID, _ fixture: Fixture) throws -> WorkToShowFirst.Item {
        let found = WorkToShowFirst.find(
            lessonID: try #require(fixture.second.id?.uuidString),
            studentIDs: [fixture.adaID, fixture.benID],
            sequences: WorkToShowFirst.Sequences(lessons: fixture.lessons),
            in: fixture.context
        )
        return try #require(found[child]?.first)
    }

    private func scheduledCheckIns(of work: CDWorkModel, in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        WorkLogService.scheduledCheckIns(of: work, in: context)
    }

    // MARK: - Logging from the present sheet

    @Test("A shared row is never logged from the list, so a classmate's part stays open")
    func sharedRowIsNotLogged() throws {
        let fixture = try fixture()
        let shared = try sharedRow(fixture)
        try fixture.context.save()
        let benItem = try item(for: fixture.benID, fixture)
        #expect(benItem.isHersAlone == false)

        #expect(throws: WorkToShowFirst.LogRefusal.sharedWithOthers) {
            try WorkToShowFirst.log(benItem, as: .done, context: fixture.context, saveCoordinator: nil)
        }
        #expect(shared.status == .active)
        #expect(shared.completedAt == nil)
        let open = QuietStudentsOrder.openStudentIDs(of: shared)
        #expect(open == [fixture.adaID, fixture.benID], "both children's parts still open")
    }

    @Test("Her own row logs, and closes for her alone")
    func ownRowLogs() throws {
        let fixture = try fixture()
        let own = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        try fixture.context.save()
        let adaItem = try item(for: fixture.adaID, fixture)
        #expect(adaItem.isHersAlone)

        let receipt = try WorkToShowFirst.log(adaItem, as: .mastered, context: fixture.context, saveCoordinator: nil)

        #expect(receipt.closed == 1)
        #expect(own.status == .mastered)
    }

    @Test("A row logged elsewhere since the list was read is not logged again")
    func loggedElsewhereIsRefused() throws {
        let fixture = try fixture()
        let own = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        try fixture.context.save()
        let adaItem = try item(for: fixture.adaID, fixture)
        // Logged in the work sheet while the present sheet still lists it.
        own.status = .done
        try fixture.context.save()
        let records = try fixture.context.count(for: CDFetchRequest(CDWorkCompletionRecord.self))

        #expect(throws: WorkToShowFirst.LogRefusal.noLongerOpen) {
            try WorkToShowFirst.log(adaItem, as: .mastered, context: fixture.context, saveCoordinator: nil)
        }
        #expect(own.status == .done, "the earlier log stands")
        #expect(try fixture.context.count(for: CDFetchRequest(CDWorkCompletionRecord.self)) == records)
    }

    // MARK: - Check Today

    @Test("With nothing planned, Check Today adds one check for today")
    func checkTodayAdds() throws {
        let fixture = try fixture()
        let own = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        try fixture.context.save()
        let adaItem = try item(for: fixture.adaID, fixture)
        let today = AppCalendar.startOfDay(Date())
        // Due today, but no check planned: the due date alone doesn't count.
        own.dueAt = today
        #expect(WorkToShowFirst.todayCheck(for: own, today: today, in: fixture.context) == .adds)
        #expect(WorkToShowFirst.checkTodayTitle(.adds) == "Check Today")

        let outcome = WorkToShowFirst.checkToday(
            adaItem, today: today, context: fixture.context, saveCoordinator: .preview
        )

        #expect(outcome == .added)
        let checks = scheduledCheckIns(of: own, in: fixture.context)
        #expect(checks.count == 1)
        #expect(checks.first.flatMap(\.date).map { AppCalendar.isSameDay($0, today) } == true)
        #expect(!fixture.context.hasChanges, "saved")
    }

    @Test("A later planned check moves to today, and the button says so; no second check is made")
    func checkTodayMovesALaterCheck() throws {
        let fixture = try fixture()
        let own = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        let today = AppCalendar.startOfDay(Date())
        let later = AppCalendar.addingDays(3, to: today)
        CDWorkCheckIn.make(for: own, on: later, in: fixture.context)
        try fixture.context.save()
        let adaItem = try item(for: fixture.adaID, fixture)

        let plan = WorkToShowFirst.todayCheck(for: own, today: today, in: fixture.context)
        #expect(plan == .movesFrom(later))
        #expect(
            WorkToShowFirst.checkTodayTitle(plan, now: today)
                == "Move \(later.formatted(.dateTime.weekday(.wide)))'s Check to Today"
        )

        let outcome = WorkToShowFirst.checkToday(
            adaItem, today: today, context: fixture.context, saveCoordinator: .preview
        )

        #expect(outcome == .moved(from: later))
        let checks = scheduledCheckIns(of: own, in: fixture.context)
        #expect(checks.count == 1, "moved, not copied")
        #expect(checks.first.flatMap(\.date).map { AppCalendar.isSameDay($0, today) } == true)
    }

    @Test("A check already on today is shown as on today's checks and left alone")
    func checkTodayLeavesTodaysCheck() throws {
        let fixture = try fixture()
        let own = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        let today = AppCalendar.startOfDay(Date())
        CDWorkCheckIn.make(for: own, on: today, in: fixture.context)
        CDWorkCheckIn.make(for: own, on: AppCalendar.addingDays(4, to: today), in: fixture.context)
        try fixture.context.save()
        let adaItem = try item(for: fixture.adaID, fixture)

        let plan = WorkToShowFirst.todayCheck(for: own, today: today, in: fixture.context)
        #expect(plan == .onToday(checked: false))
        #expect(WorkToShowFirst.checkTodayTitle(plan) == "On Today's Checks")
        #expect(
            WorkToShowFirst.checkToday(adaItem, today: today, context: fixture.context, saveCoordinator: .preview)
                == .alreadyOnToday
        )
        let days = scheduledCheckIns(of: own, in: fixture.context).compactMap(\.date).map(AppCalendar.startOfDay)
        #expect(days.sorted() == [today, AppCalendar.addingDays(4, to: today)], "the later check didn't move")
    }

    @Test("Closed work and a child who has left the class get no check")
    func checkTodayGuards() throws {
        let fixture = try fixture()
        let own = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        let bens = try work(for: fixture.benID, on: fixture.first, in: fixture.context)
        try fixture.context.save()
        let adaItem = try item(for: fixture.adaID, fixture)
        let benItem = try item(for: fixture.benID, fixture)
        own.status = .done
        fixture.ben.enrollmentStatus = .withdrawn
        try fixture.context.save()

        let context = fixture.context
        #expect(WorkToShowFirst.checkToday(adaItem, context: context, saveCoordinator: .preview) == .noLongerOpen)
        #expect(WorkToShowFirst.checkToday(benItem, context: context, saveCoordinator: .preview) == .childHasLeft)
        #expect(scheduledCheckIns(of: own, in: fixture.context).isEmpty)
        #expect(scheduledCheckIns(of: bens, in: fixture.context).isEmpty)
        #expect(
            WorkToShowFirst.message(for: .childHasLeft).text == "That child has left the class, so no check was added."
        )
    }

    @Test("Check Today on a shared row changes nothing: its one check is the whole group's")
    func checkTodayRefusesSharedRow() throws {
        let fixture = try fixture()
        let shared = try sharedRow(fixture)
        let today = AppCalendar.startOfDay(Date())
        let later = AppCalendar.addingDays(3, to: today)
        CDWorkCheckIn.make(for: shared, on: later, in: fixture.context)
        try fixture.context.save()
        let benItem = try item(for: fixture.benID, fixture)

        let outcome = WorkToShowFirst.checkToday(
            benItem, today: today, context: fixture.context, saveCoordinator: .preview
        )

        #expect(outcome == .sharedWithOthers)
        let days = scheduledCheckIns(of: shared, in: fixture.context).compactMap(\.date).map(AppCalendar.startOfDay)
        #expect(days == [later], "Ada's check didn't move")
    }

    @Test("On a weekend, Check Today means the next school day, and says which")
    func checkTodayAtTheWeekend() throws {
        let fixture = try fixture()
        let own = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        let saturday = AppCalendar.startOfDay(
            try #require(AppCalendar.shared.date(from: DateComponents(year: 2026, month: 6, day: 6)))
        )
        let monday = AppCalendar.addingDays(2, to: saturday)
        CDWorkCheckIn.make(for: own, on: monday, in: fixture.context)
        try fixture.context.save()

        let day = WorkToShowFirst.checkDay(from: saturday, in: fixture.context)
        #expect(day == monday)
        let plan = WorkToShowFirst.todayCheck(for: own, today: day, in: fixture.context)
        #expect(plan == .onToday(checked: false), "Monday's check isn't pulled back to Saturday")
        #expect(WorkToShowFirst.checkTodayTitle(plan, day: day, now: saturday) == "On Monday's Checks")
        #expect(WorkToShowFirst.checkTodayTitle(.adds, day: day, now: saturday) == "Check Monday")
        #expect(WorkToShowFirst.message(for: .added, day: day, now: saturday).text == "Added to Monday's checks")
        #expect(WorkToShowFirst.checkTodayTitle(.adds, day: monday, now: monday) == "Check Today")
    }

    @Test("A check day past the coming week reads without a possessive date, and Checked says for which day")
    func checkDayPastTheWeekReadsPlainly() throws {
        let saturday = AppCalendar.startOfDay(
            try #require(AppCalendar.shared.date(from: DateComponents(year: 2026, month: 12, day: 19)))
        )
        let monday = AppCalendar.addingDays(2, to: saturday)
        let afterBreak = AppCalendar.addingDays(18, to: saturday)
        let date = afterBreak.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

        #expect(WorkToShowFirst.checkTodayTitle(.adds, day: afterBreak, now: saturday) == "Check on \(date)")
        #expect(
            WorkToShowFirst.checkTodayTitle(.onToday(checked: false), day: afterBreak, now: saturday)
                == "On the Checks for \(date)"
        )
        #expect(
            WorkToShowFirst.checkTodayTitle(.onToday(checked: true), day: afterBreak, now: saturday)
                == "Checked for \(date)"
        )
        #expect(
            WorkToShowFirst.message(for: .added, day: afterBreak, now: saturday).text
                == "Added to the checks for \(date)"
        )
        #expect(
            WorkToShowFirst.message(for: .alreadyOnToday, day: afterBreak, now: saturday).text
                == "That work is already on the checks for \(date)"
        )
        #expect(
            WorkToShowFirst.checkTodayTitle(.onToday(checked: true), day: monday, now: saturday)
                == "Checked for Monday"
        )
        #expect(WorkToShowFirst.checkTodayTitle(.onToday(checked: true), day: saturday, now: saturday) == "Checked Today")
    }

    // MARK: - What the lists draw

    @Test("Before you start lists only children on the plan; a card counts only the chips it draws")
    func listsReadOnlyDrawnChildren() throws {
        let fixture = try fixture()
        try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        try work(for: fixture.benID, on: fixture.first, in: fixture.context)
        let found = WorkToShowFirst.find(
            lessonID: try #require(fixture.second.id?.uuidString),
            studentIDs: [fixture.adaID, fixture.benID],
            sequences: WorkToShowFirst.Sequences(lessons: fixture.lessons),
            in: fixture.context
        )
        #expect(found.count == 2)

        // Ben has come off the plan, but his work is still in the last read.
        let rows = PresentationBeforeYouStartSection.rows(students: [fixture.ada], showFirst: found)
        #expect(rows.map(\.item.studentID) == [fixture.adaID])
        #expect(PresentationBeforeYouStartSection.rows(students: [], showFirst: found).isEmpty)

        #expect(PresentationPlannerCard.showFirstCount(of: [fixture.adaID], in: found) == 1)
        #expect(PresentationPlannerCard.showFirstCount(of: [], in: found) == 0)
    }
}
