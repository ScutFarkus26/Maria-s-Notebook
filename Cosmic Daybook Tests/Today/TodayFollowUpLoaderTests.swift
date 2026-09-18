import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The due-check-in rows Today's todo list shows: list rules, not agenda
/// rules — anything still scheduled and dated is owed, and a departed child's
/// row stays, marked.
@Suite("Today Follow-Up Loader")
@MainActor
struct TodayFollowUpLoaderTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    private func enrolled(in context: NSManagedObjectContext) -> [UUID: CDStudent] {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        return Dictionary(
            context.safeFetch(request).compactMap { student in student.id.map { ($0, student) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func build(
        on selected: String, levelFilter: LevelFilter = .all, in context: NSManagedObjectContext
    ) throws -> [WorkCheckInFollowUp] {
        let (start, next) = AppCalendar.dayRange(for: try day(selected))
        let fetch = TodayDataFetcher.fetchWorkData(day: start, nextDay: next, referenceDate: start, context: context)
        return TodayFollowUpLoader.build(
            fetch: fetch, day: start, nextDay: next,
            studentsByID: enrolled(in: context),
            departedStudentsByID: TodayFollowUpLoader.fetchDepartedStudents(context: context),
            levelFilter: levelFilter
        )
    }

    @Test("A check-in before the selected day is overdue, on the day it is due, and a work shows its earliest once")
    func overdueAndDueTodayOnePerWork() throws {
        let context = try makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let ettyID = try #require(etty.id)
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stamp Game", studentID: ettyID)
        CDWorkCheckIn.make(for: work, on: try day("2026-09-09"), in: context)
        CDWorkCheckIn.make(for: work, on: try day("2026-09-04"), in: context)
        let dueToday = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead Frame", studentID: ettyID)
        CDWorkCheckIn.make(for: dueToday, on: try day("2026-09-11"), in: context)
        #expect(CoreDataTestHelpers.save(context))

        let rows = try build(on: "2026-09-11", in: context)
        #expect(rows.count == 2)
        let first = try #require(rows.first)
        let second = try #require(rows.last)
        let sep4 = try day("2026-09-04")
        #expect(first.work === work)
        #expect(first.dueDay == sep4)
        #expect(first.isOverdue)
        #expect(second.work === dueToday)
        #expect(!second.isOverdue)
    }

    @Test("Completed, skipped and future check-ins are not owed")
    func closedAndFutureExcluded() throws {
        let context = try makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let work = CoreDataTestHelpers.seedWorkModel(in: context, studentID: try #require(etty.id))
        CDWorkCheckIn.make(for: work, on: try day("2026-09-04"), status: .completed, in: context)
        CDWorkCheckIn.make(for: work, on: try day("2026-09-08"), status: .skipped, in: context)
        CDWorkCheckIn.make(for: work, on: try day("2026-09-18"), in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(try build(on: "2026-09-11", in: context).isEmpty)
    }

    @Test("A withdrawn participant marks the row, a withdrawn owner is listed and marked, an unknown owner is dropped")
    func departedChildrenAreMarkedNotHidden() throws {
        let context = try makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let naomi = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Naomi", lastName: "Levin", enrollmentStatus: .withdrawn
        )
        let ettyID = try #require(etty.id)
        let naomiID = try #require(naomi.id)
        let shared = CoreDataTestHelpers.seedWorkModel(in: context, title: "Coin cards", studentID: ettyID)
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = naomiID.uuidString
        shared.addToParticipants(participant)
        CDWorkCheckIn.make(for: shared, on: try day("2026-09-09"), in: context)

        let naomisOwn = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes", studentID: naomiID)
        CDWorkCheckIn.make(for: naomisOwn, on: try day("2026-09-10"), in: context)

        let nobodys = CoreDataTestHelpers.seedWorkModel(in: context, title: "Ghost", studentID: UUID())
        CDWorkCheckIn.make(for: nobodys, on: try day("2026-09-10"), in: context)
        #expect(CoreDataTestHelpers.save(context))

        let rows = try build(on: "2026-09-11", in: context)
        #expect(rows.count == 2)
        let sharedRow = try #require(rows.first { $0.work === shared })
        let ownRow = try #require(rows.first { $0.work === naomisOwn })
        let expectedIDs: [UUID] = [ettyID, naomiID]
        let expectedDeparted: Set<UUID> = [naomiID]
        #expect(sharedRow.studentIDs == expectedIDs)
        #expect(sharedRow.departedStudentIDs == expectedDeparted)
        #expect(sharedRow.hasDepartedParticipant)
        #expect(ownRow.departedStudentIDs == expectedDeparted)
        #expect(!rows.contains { $0.work === nobodys })
    }

    @Test("The level filter drops an upper owner's row and .all keeps it")
    func levelFilterFollowsTheOwner() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Katz", level: .upper)
        let work = CoreDataTestHelpers.seedWorkModel(in: context, studentID: try #require(ora.id))
        CDWorkCheckIn.make(for: work, on: try day("2026-09-10"), in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(try build(on: "2026-09-11", levelFilter: .lower, in: context).isEmpty)
        #expect(try build(on: "2026-09-11", levelFilter: .upper, in: context).count == 1)
        #expect(try build(on: "2026-09-11", levelFilter: .all, in: context).count == 1)
    }

    @Test("Rows come earliest day first, then by the owner's first name")
    func orderIsDayThenName() throws {
        let context = try makeContext()
        let zahava = CoreDataTestHelpers.seedStudent(in: context, firstName: "Zahava", lastName: "Wechsler")
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        let zahavaID = try #require(zahava.id)
        let avitalID = try #require(avital.id)
        let zahavaOld = CoreDataTestHelpers.seedWorkModel(in: context, title: "Old", studentID: zahavaID)
        CDWorkCheckIn.make(for: zahavaOld, on: try day("2026-09-04"), in: context)
        let zahavaNew = CoreDataTestHelpers.seedWorkModel(in: context, title: "New", studentID: zahavaID)
        CDWorkCheckIn.make(for: zahavaNew, on: try day("2026-09-09"), in: context)
        let avitalNew = CoreDataTestHelpers.seedWorkModel(in: context, title: "New", studentID: avitalID)
        CDWorkCheckIn.make(for: avitalNew, on: try day("2026-09-09"), in: context)
        #expect(CoreDataTestHelpers.save(context))

        let rows = try build(on: "2026-09-11", in: context)
        let titles: [String] = rows.map(\.work.title)
        let owners: [UUID?] = rows.map { $0.studentIDs.first }
        #expect(titles == ["Old", "New", "New"])
        #expect(owners == [zahavaID, avitalID, zahavaID])
    }

    @Test("reload fills the view model; completing empties it; rescheduling moves dueAt with the check-in")
    func viewModelRoundTrip() throws {
        let context = try makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let ettyID = try #require(etty.id)
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stamp Game", studentID: ettyID)
        let today = AppCalendar.startOfDay(Date())
        let checkIn = CDWorkCheckIn.make(for: work, on: AppCalendar.addingDays(-2, to: today), in: context)
        #expect(CoreDataTestHelpers.save(context))
        let service = WorkCheckInService(context: context)

        let viewModel = TodayViewModel(context: context)
        viewModel.reload()
        #expect(viewModel.followUpCheckIns.count == 1)
        #expect(viewModel.followUpCheckIns.first?.isOverdue == true)
        // Not on the agenda any more — one home for a due check-in.
        #expect(!viewModel.agendaItems.contains(where: isScheduledWork))

        let nextWeek = AppCalendar.addingDays(7, to: today)
        try service.reschedule(checkIn, to: nextWeek)
        work.dueAt = nextWeek
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reload()
        #expect(viewModel.followUpCheckIns.isEmpty)
        #expect(work.dueAt == nextWeek)

        try service.reschedule(checkIn, to: today)
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reload()
        #expect(viewModel.followUpCheckIns.count == 1)
        #expect(viewModel.followUpCheckIns.first?.isOverdue == false)

        try service.markCompleted(checkIn, note: nil, at: Date())
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reload()
        #expect(viewModel.followUpCheckIns.isEmpty)
    }

    private func isScheduledWork(_ item: AgendaItem) -> Bool {
        if case .scheduledWork = item { return true }
        return false
    }
}
