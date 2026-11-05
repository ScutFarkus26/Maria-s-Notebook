import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Today's findings from the bug hunt of 2026-11-03: calendar events after a
/// sync (#48), to-dos on weekends and the + button's day (#53, #54), hidden test
/// students (#55), and the absent mover's year-plan entries.
@Suite("Today fixes 2026-11-03")
@MainActor
struct TodayFix1103D {

    // MARK: - #48 Calendar events after a sync

    @Test("A calendar event the sync saved reloads Today")
    func eventKitSyncReloadsToday() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let viewModel = TodayViewModel(context: stack.viewContext)
        viewModel.reload()
        let afterFirst = viewModel.reloadCount

        // The Calendar sync adds an event. (The Reminders half of #48 went
        // with the Reminders sync, round-two Simplify.)
        let syncContext = stack.newBackgroundContext()
        syncContext.performAndWait {
            let event = CDCalendarEvent(context: syncContext)
            event.title = "Field trip"
            event.startDate = Date()
            event.endDate = Date().addingTimeInterval(3600)
            _ = syncContext.safeSave()
        }
        viewModel.scheduleReloadIfInputsChanged()
        await viewModel.reloadTask?.value
        #expect(viewModel.reloadCount == afterFirst + 1)
    }

    // MARK: - #53, #54 To-dos on days Today moves

    private typealias Section = TodayTodosSectionView<EmptyView>

    private func todo(
        _ title: String, due: Date? = nil, scheduled: Date? = nil, in context: NSManagedObjectContext
    ) -> CDTodoItem {
        let item = CDTodoItem(context: context)
        item.title = title
        item.dueDate = due?.addingTimeInterval(9 * 3600)
        item.scheduledDate = scheduled?.addingTimeInterval(9 * 3600)
        return item
    }

    @Test("On a Saturday, Today (showing Friday) lists a to-do planned for Saturday")
    func saturdayTodoShowsOnSaturday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let friday = try CoreDataTestHelpers.day("2026-11-06")
        let saturday = try CoreDataTestHelpers.day("2026-11-07")
        let paint = todo("Buy paint", scheduled: saturday, in: context)
        let fridays = todo("Call the office", due: friday, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let day = TodayTodoDay(shownDay: friday, realDay: saturday, schoolDayForRealDay: friday)
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = Section.fetchPredicate(for: day)
        let partition = Section.partition(context.safeFetch(request), day: day, calendar: AppCalendar.shared)
        #expect(partition.dueOnDay.map(\.title) == [paint.title])
        // Friday has passed: its deadline is overdue, as on the Todos screen.
        #expect(partition.overdue.map(\.title) == [fridays.title])
        // The + button's to-do lands on Saturday, so it shows here.
        #expect(day.newTodoDate == saturday)
    }

    @Test("On a Sunday, Today (showing Monday) lists Sunday's to-dos as today's, not overdue, and Monday's")
    func sundayTodosAreNotOverdue() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let saturday = try CoreDataTestHelpers.day("2026-11-07")
        let sunday = try CoreDataTestHelpers.day("2026-11-08")
        let monday = try CoreDataTestHelpers.day("2026-11-09")
        _ = todo("Due Saturday", due: saturday, in: context)
        _ = todo("Due Sunday", due: sunday, in: context)
        _ = todo("Planned Monday", scheduled: monday, in: context)
        _ = todo("Planned Tuesday", scheduled: AppCalendar.addingDays(1, to: monday), in: context)
        #expect(CoreDataTestHelpers.save(context))

        let day = TodayTodoDay(shownDay: monday, realDay: sunday, schoolDayForRealDay: monday)
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = Section.fetchPredicate(for: day)
        let partition = Section.partition(context.safeFetch(request), day: day, calendar: AppCalendar.shared)
        #expect(partition.overdue.map(\.title) == ["Due Saturday"])
        #expect(Set(partition.dueOnDay.map(\.title)) == ["Due Sunday", "Planned Monday"])
        #expect(!partition.all.contains { $0.title == "Planned Tuesday" })
        // The screen shows Monday; the + button's to-do is Monday's.
        #expect(day.newTodoDate == monday)
    }

    @Test("On a school day, or a day the teacher went to, the to-dos and the + button follow the shown day")
    func shownDayRulesOtherwise() throws {
        let tuesday = try CoreDataTestHelpers.day("2026-11-03")
        let wednesday = try CoreDataTestHelpers.day("2026-11-04")
        let today = TodayTodoDay(shownDay: wednesday, realDay: wednesday, schoolDayForRealDay: wednesday)
        #expect(today.overdueBefore == wednesday && today.lastDay == wednesday)
        #expect(today.newTodoDate == wednesday)
        let back = TodayTodoDay(shownDay: tuesday, realDay: wednesday, schoolDayForRealDay: wednesday)
        #expect(back.overdueBefore == tuesday && back.lastDay == tuesday)
        #expect(back.newTodoDate == tuesday)
    }

    // MARK: - #55 Hidden test students

    private final class HiddenNames {
        var names: Set<String>
        init(_ names: Set<String>) { self.names = names }
    }

    @Test("Hidden test students are out of Today's students, meetings and notes, and a change to the list takes effect")
    func hiddenTestStudentsLeaveToday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let pat = CoreDataTestHelpers.seedStudent(in: context, firstName: "Pat", lastName: "Tester")
        let mayaID = try #require(maya.id)
        let patID = try #require(pat.id)
        #expect(CoreDataTestHelpers.save(context))

        let hidden = HiddenNames(["pat tester"])
        let cache = TodayCacheManager(hiddenNames: { hidden.names })
        #expect(Set(cache.enrolledStudents(ids: [mayaID, patID], context: context).keys) == [mayaID])
        cache.loadStudentsIfNeeded(ids: [mayaID, patID], context: context)
        #expect(Set(cache.studentsByID.keys) == [mayaID])
        #expect(cache.hiddenStudentIDs(context: context) == [patID])

        // Pat's meeting and the note about only her leave; Maya's and the group's stay.
        let patsMeeting = CDScheduledMeeting(context: context)
        patsMeeting.studentID = patID.uuidString
        let mayasMeeting = CDScheduledMeeting(context: context)
        mayasMeeting.studentID = mayaID.uuidString
        let patsNote = CoreDataTestHelpers.seedNote(in: context, body: "Pat tried the bead frame")
        patsNote.scope = .student(patID)
        let bothNote = CoreDataTestHelpers.seedNote(in: context, body: "Both at the bead frame")
        bothNote.scope = .students([mayaID, patID])
        let classNote = CoreDataTestHelpers.seedNote(in: context, body: "Quiet morning")
        let hiddenIDs = cache.hiddenStudentIDs(context: context)
        #expect(TodayHiddenStudents.meetings([patsMeeting, mayasMeeting], hiding: hiddenIDs) == [mayasMeeting])
        #expect(TodayHiddenStudents.notes([patsNote, bothNote, classNote], hiding: hiddenIDs) == [bothNote, classNote])

        // The teacher hides Maya instead: the cached children follow at once.
        hidden.names = ["maya stone"]
        cache.loadStudentsIfNeeded(ids: [mayaID, patID], context: context)
        #expect(Set(cache.studentsByID.keys) == [patID])
        #expect(cache.hiddenStudentIDs(context: context) == [mayaID])
    }

    // MARK: - Absent mover and the year plan

    @Test("Moving absent children to tomorrow takes their year-plan entries to tomorrow, and Undo brings them back")
    func absentMoveCarriesYearPlanEntries() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game", area: "Math", sequence: "Operations"
        )
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya")
        let theo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Theo")
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let today = AppCalendar.startOfDay(Date())
        let tomorrow = try #require(AppCalendar.shared.date(byAdding: .day, value: 1, to: today))
        let shared = PresentationFactory.makeScheduled(
            lesson: lesson, students: [maya, theo], scheduledFor: today, context: context
        )
        let adas = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada], scheduledFor: today, context: context
        )
        func entry(for student: CDStudent, promotedInto assignment: CDLessonAssignment) throws -> CDYearPlanEntry {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = try #require(student.id).uuidString
            entry.lessonID = try #require(lesson.id).uuidString
            entry.sequenceGroupKey = "Math::Operations"
            entry.status = .promoted
            entry.promotedAssignmentID = try #require(assignment.id).uuidString
            entry.plannedDate = today
            return entry
        }
        let theoEntry = try entry(for: theo, promotedInto: shared)
        let adaEntry = try entry(for: ada, promotedInto: adas)
        try context.save()

        // Theo goes onto a plan of his own; Ada's lesson moves whole.
        let theoID = try #require(theo.id)
        let adaID = try #require(ada.id)
        let receipt = try #require(try TodayAbsentMover.moveAbsent(
            from: [shared, adas], absent: [theoID, adaID], to: tomorrow,
            context: context, saveCoordinator: coordinator
        ))
        #expect(theoEntry.promotedAssignmentID != shared.id?.uuidString)
        #expect(theoEntry.plannedDate == tomorrow)
        #expect(adaEntry.plannedDate == tomorrow)

        try TodayAbsentMover.undo(receipt, context: context, saveCoordinator: coordinator)
        #expect(theoEntry.plannedDate == today)
        #expect(adaEntry.plannedDate == today)
        #expect(theoEntry.promotedAssignmentID == shared.id?.uuidString)
    }
}
