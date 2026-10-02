import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Today's Gone quiet section (phase 4): its words and thresholds, its rows
/// and true count through a real reload, scheduling a check-in off it, and
/// linked todos folding onto its rows and out of the Todos list.
@Suite("Today gone quiet")
@MainActor
struct TodayGoneQuietTests {

    // MARK: - Fixtures

    private struct Room {
        let context: NSManagedObjectContext
        let studentID: UUID
    }

    private func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        return Room(context: context, studentID: try #require(etty.id))
    }

    /// Open work last touched `daysAgo` calendar days back, one child's row.
    @discardableResult
    private func seedWork(_ title: String, daysAgo: Int, in room: Room) -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(in: room.context, title: title, studentID: room.studentID)
        work.id = UUID()
        work.status = .active
        work.checkInStyle = .individual
        let touched = AppCalendar.addingDays(-daysAgo, to: AppCalendar.startOfDay(Date()))
        work.createdAt = touched
        work.lastTouchedAt = touched
        return work
    }

    private func reloaded(_ room: Room) -> TodayViewModel {
        let viewModel = TodayViewModel(context: room.context)
        viewModel.reload()
        return viewModel
    }

    private func quietWorkIDs(_ viewModel: TodayViewModel) -> [UUID] {
        viewModel.goneQuietItems.compactMap { item in
            if case .followUp(let followUp) = item { return followUp.work.id }
            return nil
        }
    }

    // MARK: - Words

    @Test("The age chip reads \"19d quiet\" and turns orange from 18 days")
    func ageChip() {
        #expect(TodayGoneQuiet.ageText(days: 19) == "19d quiet")
        #expect(TodayGoneQuiet.isLongQuiet(days: 17) == false)
        #expect(TodayGoneQuiet.isLongQuiet(days: 18))
        #expect(TodayGoneQuiet.isLongQuiet(days: 40))
    }

    @Test("The header names the stale threshold")
    func subtitle() {
        #expect(TodayGoneQuiet.subtitle == "open work nobody has touched in \(AgingPolicy.staleDays)+ days")
        #expect(TodayGoneQuiet.title == "Gone quiet")
    }

    // MARK: - Rows and the true count

    @Test("\"See all N\" names every quiet work, not just the 15 rows kept")
    func seeAllUsesTheTrueCount() throws {
        let room = try makeRoom()
        for index in 0..<20 {
            seedWork("Work \(index)", daysAgo: 60 + index, in: room)
        }
        #expect(CoreDataTestHelpers.save(room.context))

        let viewModel = reloaded(room)

        #expect(viewModel.goneQuietItems.count == TodayScheduleBuilder.staleRowLimit)
        #expect(viewModel.staleTotalCount == 20)
        #expect(TodayGoneQuiet.seeAllText(totalCount: viewModel.staleTotalCount) == "See all 20")
    }

    @Test("Quiet work has its own section, most quiet first, and is off the Lessons list")
    func quietWorkLeavesTheAgenda() throws {
        let room = try makeRoom()
        let quiet = seedWork("Map of Africa", daysAgo: 40, in: room)
        let quieter = seedWork("Stamp Game", daysAgo: 80, in: room)
        seedWork("Bead Chain", daysAgo: 0, in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        let viewModel = reloaded(room)

        // Ages clamp to the school year's first day, so two old works can tie:
        // compare the set, then the order by age.
        #expect(Set(quietWorkIDs(viewModel)) == Set([quieter.id, quiet.id].compactMap { $0 }))
        let ages = viewModel.staleFollowUps.map(\.daysSinceTouch)
        #expect(ages == ages.sorted(by: >))
        #expect(viewModel.agendaItems.isEmpty)
    }

    @Test("A group lesson's children share a row where the most quiet of them first appears")
    func groupsKeepTheirPlace() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lessonID = UUID()
        func item(_ days: Int, style: CheckInStyle, lesson: UUID = UUID()) -> FollowUpWorkItem {
            let work = CoreDataTestHelpers.seedWorkModel(in: context, lessonID: lesson)
            work.id = UUID()
            work.checkInStyle = style
            return FollowUpWorkItem(work: work, daysSinceTouch: days)
        }
        let loneQuietest = item(40, style: .individual)
        let groupFirst = item(30, style: .group, lesson: lessonID)
        let lone = item(20, style: .individual)
        let groupSecond = item(12, style: .group, lesson: lessonID)

        let rows = TodayAgendaBuilder.groupFollowUpWork([loneQuietest, groupFirst, lone, groupSecond])

        #expect(rows.map(\.itemType) == [.followUp, .groupedFollowUp, .followUp])
        #expect(rows.map(\.id) == [loneQuietest.id, groupFirst.id, lone.id])
    }

    @Test("Scheduling a check-in takes the work off Gone quiet, on the day picked")
    func schedulingTakesTheRowOff() throws {
        let room = try makeRoom()
        let work = seedWork("Stamp Game", daysAgo: 60, in: room)
        // A check already done stays done: the scheduler makes a new one.
        let done = CDWorkCheckIn.make(
            for: work, on: AppCalendar.addingDays(-60, to: Date()), purpose: "progressCheck",
            status: .completed, in: room.context
        )
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(quietWorkIDs(reloaded(room)) == [work.id].compactMap { $0 })

        let day = AppCalendar.addingDays(3, to: AppCalendar.startOfDay(Date()))
        TodayCheckInScheduler.schedule([work], on: day, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let scheduled = WorkLogService.scheduledCheckIns(of: work, in: room.context)
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.date == day)
        #expect(work.dueAt == day)
        #expect(done.status == .completed)
        #expect(quietWorkIDs(reloaded(room)).isEmpty)
    }

    // MARK: - Linked todos

    @Test("A todo linked to quiet work folds onto its row and leaves the Todos list; one for other work stays")
    func linkedTodosFold() throws {
        let room = try makeRoom()
        let quiet = seedWork("Stamp Game", daysAgo: 60, in: room)
        let fresh = seedWork("Bead Chain", daysAgo: 0, in: room)
        let today = AppCalendar.startOfDay(Date())
        func todo(_ title: String, work: CDWorkModel, due: Date?) -> CDTodoItem {
            let todo = CDTodoItem(context: room.context)
            todo.id = UUID()
            todo.title = title
            todo.dueDate = due
            todo.linkedWorkItemID = work.id?.uuidString
            return todo
        }
        let onRow = todo("Check the stamp game", work: quiet, due: AppCalendar.addingDays(-1, to: today))
        let offScreen = todo("Check the bead chain", work: fresh, due: today)
        #expect(CoreDataTestHelpers.save(room.context))

        let viewModel = reloaded(room)
        let quietID = try #require(quiet.id)
        let row = try #require(viewModel.linkedTodos.byWork[quietID])
        #expect(row.count == 1)
        #expect(row.isOverdue)
        #expect(viewModel.linkedTodos.hiddenTodoIDs == Set([onRow.id].compactMap { $0 }))

        // The Todos section's partition drops the folded todo and keeps the other.
        let partition = TodayTodosSectionView<EmptyView>.partition(
            [onRow, offScreen], date: today, calendar: AppCalendar.shared,
            hiding: viewModel.linkedTodos.hiddenTodoIDs
        )
        #expect(partition.all.map { $0.objectID } == [offScreen.objectID])
    }

    @Test("A group row shows its children's linked todos together, the soonest date first")
    func groupRowTodos() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        let day = { (month: Int, day: Int) in
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9)) ?? .distantPast
        }
        let first = UUID()
        let second = UUID()
        let none = UUID()
        let linked = TodayLinkedTodos.build(
            todos: [
                .init(id: UUID(), linkedWorkItemID: first.uuidString, dueDate: day(9, 25)),
                .init(id: UUID(), linkedWorkItemID: second.uuidString, dueDate: day(9, 18)),
                .init(id: UUID(), linkedWorkItemID: second.uuidString, dueDate: nil)
            ],
            workIDsOnScreen: [first, second, none], referenceDay: day(9, 20), calendar: calendar
        )

        let row = try #require(linked.rowTodos(for: [first, second, none], calendar: calendar))
        #expect(row.count == 3)
        #expect(row.summary == "3 todos · Sep 18")
        #expect(row.isOverdue)
        #expect(linked.rowTodos(for: [none], calendar: calendar) == nil)
        #expect(linked.rowTodos(for: [first], calendar: calendar) == linked.byWork[first])
    }
}
