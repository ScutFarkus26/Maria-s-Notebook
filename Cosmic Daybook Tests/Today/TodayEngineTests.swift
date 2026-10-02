import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// The Today redesign's engine pass (phase 1): fewer reads per reload, the
/// same rows. These pin the pure pieces — the miss caching, the true stale
/// count, the narrowed todo fetch, the absent set, the plan set — and the
/// change gate that reloads Today after an edit made elsewhere.
@Suite("Today engine")
@MainActor
struct TodayEngineTests {

    // MARK: - Roster snapshot

    @Test("A departed or unknown child reads the student table once, until a student changes")
    func missesAreCached() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let naomi = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Naomi", lastName: "Levin", enrollmentStatus: .withdrawn
        )
        #expect(CoreDataTestHelpers.save(context))
        let ettyID = try #require(etty.id)
        let naomiID = try #require(naomi.id)

        let cache = TodayCacheManager()
        for _ in 0..<4 {
            cache.loadStudentsIfNeeded(ids: [ettyID, naomiID, UUID()], context: context)
        }
        #expect(Set(cache.studentsByID.keys) == [ettyID])
        #expect(Array(cache.departedStudents(context: context).keys) == [naomiID])
        #expect(Array(cache.enrolledStudents(ids: [ettyID, naomiID], context: context).keys) == [ettyID])
        #expect(cache.tableFetchCount == 1)

        // A new child arrives (an import, another window): the snapshot is
        // dropped and the child resolves on the next lookup.
        let noa = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Cohen")
        #expect(CoreDataTestHelpers.save(context))
        let noaID = try #require(noa.id)
        cache.loadStudentsIfNeeded(ids: [naomiID, noaID], context: context)
        #expect(cache.studentsByID[noaID] === noa)
        #expect(cache.tableFetchCount == 2)
        cache.loadStudentsIfNeeded(ids: [naomiID, noaID], context: context)
        #expect(cache.tableFetchCount == 2)
    }

    @Test("A lesson id with no lesson reads the lesson table once, until a lesson changes")
    func lessonMissesAreCached() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        #expect(CoreDataTestHelpers.save(context))
        let lessonID = try #require(lesson.id)
        let orphan = UUID()

        let cache = TodayCacheManager()
        cache.loadLessonsIfNeeded(ids: [lessonID, orphan], context: context)
        cache.loadLessonsIfNeeded(ids: [lessonID, orphan], context: context)
        #expect(cache.lessonsByID[lessonID] === lesson)
        #expect(cache.tableFetchCount == 1)

        let late = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame")
        late.id = orphan
        #expect(CoreDataTestHelpers.save(context))
        cache.loadLessonsIfNeeded(ids: [lessonID, orphan], context: context)
        #expect(cache.lessonsByID[orphan] === late)
        #expect(cache.tableFetchCount == 2)
    }

    // MARK: - Gone quiet

    @Test("Stale rows keep the top 15, and the total counts every stale work")
    func staleTotalCount() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let ettyID = try #require(etty.id)
        let longAgo = AppCalendar.addingDays(-120, to: Date())
        for index in 0..<20 {
            let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Work \(index)", studentID: ettyID)
            work.id = UUID()
            work.status = .active
            work.createdAt = longAgo
            work.lastTouchedAt = AppCalendar.addingDays(index, to: longAgo)
        }
        #expect(CoreDataTestHelpers.save(context))
        let works = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        let expected = works.filter { WorkAgingPolicy.isStale($0, using: context) }.count
        try #require(expected > TodayScheduleBuilder.staleRowLimit)

        let result = TodayScheduleBuilder.buildSchedule(
            workItems: works, checkInsByWork: [:], notesByWork: [:],
            studentsByID: [ettyID: etty], levelFilter: .all, referenceDate: Date(), context: context
        )
        #expect(result.stale.count == TodayScheduleBuilder.staleRowLimit)
        #expect(result.staleTotalCount == expected)
    }

    // MARK: - Todos

    /// One todo of each shape the Todos section tells apart, around `day`.
    private func seedTodos(around day: Date, in context: NSManagedObjectContext) {
        let at = { (offset: Int) in AppCalendar.addingDays(offset, to: day).addingTimeInterval(9 * 3600) }
        func todo(
            _ title: String, due: Int? = nil, scheduled: Int? = nil,
            priority: TodoPriority = .none, someday: Bool = false, done: Bool = false
        ) {
            let item = CDTodoItem(context: context)
            item.title = title
            item.dueDate = due.map(at)
            item.scheduledDate = scheduled.map(at)
            item.priority = priority
            item.isSomeday = someday
            item.isCompleted = done
        }
        todo("Scheduled today", scheduled: 0)
        todo("Scheduled tomorrow", scheduled: 1)
        todo("Scheduled yesterday", scheduled: -1)
        todo("Due today", due: 0)
        todo("Due tomorrow", due: 1)
        todo("Due next week", due: 7)
        todo("Overdue", due: -3)
        todo("Overdue, scheduled today", due: -3, scheduled: 0)
        todo("Overdue, rescheduled later", due: -3, scheduled: 2)
        todo("Overdue high, rescheduled later", due: -3, scheduled: 2, priority: .high)
        todo("Undated high", priority: .high)
        todo("Undated medium", priority: .medium)
        todo("Future high", due: 10, priority: .high)
        todo("Someday high", priority: .high, someday: true)
        todo("Done today", due: 0, done: true)
        todo("Undated")
    }

    @Test("The narrowed todo fetch shows exactly what the whole open-todo fetch showed")
    func todoPredicateMatchesTheOldFetch() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let day = try CoreDataTestHelpers.day("2026-09-16")
        seedTodos(around: day, in: context)
        #expect(CoreDataTestHelpers.save(context))

        typealias Section = TodayTodosSectionView<EmptyView>
        let sort = [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: false)]
        for offset in -2...3 {
            let selected = AppCalendar.addingDays(offset, to: day)
            let wide = CDFetchRequest(CDTodoItem.self)
            wide.predicate = NSPredicate(format: "isCompleted == NO")
            wide.sortDescriptors = sort
            let narrow = CDFetchRequest(CDTodoItem.self)
            narrow.predicate = Section.fetchPredicate(selectedDay: AppCalendar.startOfDay(selected))
            narrow.sortDescriptors = sort

            let narrowRows = context.safeFetch(narrow)
            let before = Section.partition(context.safeFetch(wide), date: selected, calendar: AppCalendar.shared)
            let after = Section.partition(narrowRows, date: selected, calendar: AppCalendar.shared)
            #expect(after.all.map(\.title) == before.all.map(\.title), "day offset \(offset)")
            #expect(after.overdue.map(\.title) == before.overdue.map(\.title))
            #expect(after.dueOnDay.map(\.title) == before.dueOnDay.map(\.title))
            #expect(after.highPriority.map(\.title) == before.highPriority.map(\.title))
            #expect(!narrowRows.contains { $0.title == "Undated" || $0.title == "Due next week" })
        }
    }

    // MARK: - Attendance and plans

    @Test("Absent children are every absent record, one per child")
    func absentStudentIDs() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (day, next) = AppCalendar.dayRange(for: Date())
        let maya = UUID()
        let avi = UUID()
        let shira = UUID()
        CoreDataTestHelpers.seedAttendance(in: context, studentID: maya, date: day).status = .absent
        CoreDataTestHelpers.seedAttendance(in: context, studentID: avi, date: day).status = .present
        let first = CoreDataTestHelpers.seedAttendance(in: context, studentID: shira, date: day)
        first.status = .absent
        first.modifiedAt = day
        let second = CoreDataTestHelpers.seedAttendance(in: context, studentID: shira, date: day)
        second.status = .tardy
        second.modifiedAt = day.addingTimeInterval(60)
        #expect(CoreDataTestHelpers.save(context))

        let records = TodayDataFetcher.fetchAttendance(day: day, nextDay: next, context: context).records
        #expect(TodayAttendanceLoader.absentStudentIDs(in: records) == [maya])
    }

    @Test("Only lessons with a plan document get the plan button")
    func lessonIDsWithPlan() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let withPlan = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        withPlan.pagesFileRelativePath = "Lessons/Stamp Game.pages"
        let without = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame")
        let withPlanID = try #require(withPlan.id)
        let withoutID = try #require(without.id)
        let lessons = [withPlanID, withoutID, UUID()].map {
            PresentationFactory.makeDraft(lessonID: $0, studentIDs: [UUID()], context: context)
        }

        let result = TodayLessonsLoader.lessonIDsWithPlan(
            for: lessons, lessonsByID: [withPlanID: withPlan, withoutID: without]
        )
        #expect(result == [withPlanID])
    }

    // MARK: - Reload after an edit elsewhere

    @Test("An edit saved elsewhere reloads once; Today's own reloaded save does not reload again")
    func changeGate() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stamp Game")
        work.id = UUID()
        #expect(CoreDataTestHelpers.save(context))
        let viewModel = TodayViewModel(context: context)
        viewModel.reload()
        let afterFirst = viewModel.reloadCount

        // Nothing changed: the gated request reloads nothing.
        viewModel.scheduleReloadIfInputsChanged()
        try await Task.sleep(for: .milliseconds(700))
        #expect(viewModel.reloadCount == afterFirst)

        // Another window saves a work: one reload.
        work.title = "Stamp Game (golden beads)"
        #expect(CoreDataTestHelpers.save(context))
        viewModel.scheduleReloadIfInputsChanged()
        viewModel.scheduleReloadIfInputsChanged()
        try await Task.sleep(for: .milliseconds(700))
        #expect(viewModel.reloadCount == afterFirst + 1)

        // Today saves and reloads for itself; the save's signal then asks
        // for nothing more.
        work.title = "Stamp Game"
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reload()
        viewModel.scheduleReloadIfInputsChanged()
        try await Task.sleep(for: .milliseconds(700))
        #expect(viewModel.reloadCount == afterFirst + 2)

        // A pending outright reload survives a gated request replacing it.
        viewModel.scheduleReload()
        viewModel.scheduleReloadIfInputsChanged()
        try await Task.sleep(for: .milliseconds(700))
        #expect(viewModel.reloadCount == afterFirst + 3)
    }
}
