import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The attendance rules every path goes through (`CDAttendanceStore.mark`),
/// driven through Claude's `mark_attendance`, which skipped them, and the
/// tally the reports count with (domain-logic review 2026-11-20, R5 and R19).
@Suite("Attendance mark rules")
@MainActor
struct AttendanceMarkRulesTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func markTool(_ tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == "mark_attendance" })
    }

    private func records(for student: CDStudent, in context: NSManagedObjectContext) -> [CDAttendanceRecord] {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "studentID == %@", student.cloudKitKey)
        return context.safeFetch(request)
    }

    /// The first weekday at least a week after today, as `mark_attendance` reads a date.
    private func weekdayAhead() -> (date: Date, text: String) {
        var day = AppCalendar.addingDays(7, to: AppCalendar.startOfDay(Date()))
        while [1, 7].contains(AppCalendar.shared.component(.weekday, from: day)) {
            day = AppCalendar.addingDays(1, to: day)
        }
        return (day, MCPNotebookTools.isoDay.string(from: day))
    }

    @Test("Claude's unmarked clears every copy of the day, so a duplicate's mark doesn't win back")
    func unmarkBeatsADuplicatesMark() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stein")
        let day = try CoreDataTestHelpers.day("2026-09-14")
        for minutes in [0.0, 5.0] {
            let copy = CDAttendanceRecord(context: context)
            copy.studentID = maya.cloudKitKey
            copy.date = day
            copy.status = .present
            copy.modifiedAt = day.addingTimeInterval(8 * 3_600 + minutes * 60)
        }
        try context.save()

        _ = try await markTool(tools).handler([
            "student_name": .string("Maya"), "status": .string("unmarked"), "date": .string("2026-09-14")
        ])

        let winner = records(for: maya, in: context).deduplicatedPerStudentDay().first
        #expect(winner?.status == .unmarked)
        #expect(records(for: maya, in: context).allSatisfy { $0.status == .unmarked })
    }

    @Test("Claude refuses a child who left before the day, and writes nothing")
    func refusesADepartedChild() async throws {
        let (tools, context) = try makeTools()
        let rivka = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Gold", enrollmentStatus: .withdrawn,
            dateWithdrawn: try CoreDataTestHelpers.day("2026-09-01")
        )
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await markTool(tools).handler([
                "student_name": .string("Rivka Gold"), "status": .string("present"), "date": .string("2026-09-14")
            ])
        }
        #expect(records(for: rivka, in: context).isEmpty)
    }

    @Test("Claude refuses present on a day still to come, and takes an absence")
    func refusesPresentAhead() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stein")
        CoreDataTestHelpers.save(context)
        let ahead = weekdayAhead()

        await #expect(throws: MCPToolError.self) {
            _ = try await markTool(tools).handler([
                "student_name": .string("Maya"), "status": .string("present"), "date": .string(ahead.text)
            ])
        }
        #expect(records(for: maya, in: context).isEmpty)

        _ = try await markTool(tools).handler([
            "student_name": .string("Maya"), "status": .string("absent"), "date": .string(ahead.text)
        ])
        #expect(records(for: maya, in: context).first?.status == .absent)
    }

    @Test("Claude refuses mark_all_present on a day still to come")
    func refusesEveryonePresentAhead() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stein")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await markTool(tools).handler([
                "mark_all_present": .bool(true), "date": .string(weekdayAhead().text)
            ])
        }
        #expect(records(for: maya, in: context).isEmpty)
    }

    @Test("Absent from Claude claims Close Arrival's automatic absence as the guide's")
    func absentClaimsCloseArrivalsAbsence() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stein")
        let day = try CoreDataTestHelpers.day("2026-09-14")
        let store = CDAttendanceStore(context: context, calendar: AppCalendar.shared)
        let closed = try store.markUnmarkedAbsent(for: day, students: [maya])
        try context.save()
        #expect(closed.count == 1)
        #expect(closed.allSatisfy(AttendanceDeduplication.isAutomaticAbsence))

        _ = try await markTool(tools).handler([
            "student_name": .string("Maya"), "status": .string("absent"), "date": .string("2026-09-14")
        ])

        let record = try #require(records(for: maya, in: context).first)
        #expect(record.status == .absent)
        #expect(AttendanceDeduplication.isAutomaticAbsence(record) == false)
    }

    @Test("The class summary drops the marks of a day later made a day off")
    func tallyDropsADayTurnedOff() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stein")
        let monday = try CoreDataTestHelpers.day("2026-09-14")
        let tuesday = try CoreDataTestHelpers.day("2026-09-15")
        for day in [monday, tuesday] {
            let record = CDAttendanceRecord(context: context)
            record.studentID = maya.cloudKitKey
            record.date = day
            record.status = .absent
        }
        let storm = CDNonSchoolDay(context: context)
        storm.date = tuesday
        try context.save()

        let summary = AttendanceInsightsService.classSummary(in: monday...tuesday, students: [maya], context: context)
        #expect(summary.absentCount == 1)
        #expect(summary.schoolDays == 1)
    }
}

/// The store's mark on its own, the tally behind the reports, and the
/// paired-field rule (`CDAttendanceRecord.normalize`).
@Suite("Attendance store mark")
@MainActor
struct AttendanceStoreMarkTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let store: CDAttendanceStore
        let maya: CDStudent
    }

    private func setUp() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stein")
        try context.save()
        return Fixture(context: context, store: CDAttendanceStore(context: context, calendar: AppCalendar.shared), maya: maya)
    }

    private func allRecords(_ context: NSManagedObjectContext) -> [CDAttendanceRecord] {
        context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
    }

    @Test("Clearing a child with no record writes nothing")
    func unmarkWithoutRecordWritesNothing() throws {
        let fixture = try setUp(), context = fixture.context, store = fixture.store, maya = fixture.maya
        let outcome = try store.mark(student: maya, status: .unmarked, on: try CoreDataTestHelpers.day("2026-09-14"))
        #expect(outcome.record == nil)
        #expect(outcome.changed == false)
        #expect(allRecords(context).isEmpty)
    }

    @Test("A test student this device hides is refused")
    func refusesAHiddenTestStudent() throws {
        let fixture = try setUp(), context = fixture.context, store = fixture.store
        // "Lil Dan D", one of the names hidden until the teacher edits the list.
        let tester = CoreDataTestHelpers.seedStudent(in: context, firstName: "Lil", lastName: "Dan D")
        try #require(TestStudentsFilter.filterVisible([tester]).isEmpty)
        #expect(throws: AttendanceMarkRefusal.notOnRoll(.testStudent)) {
            try store.mark(student: tester, status: .present, on: try CoreDataTestHelpers.day("2026-09-14"))
        }
        #expect(allRecords(context).isEmpty)
    }

    @Test("A child who hasn't started is refused as not started")
    func refusesBeforeTheStart() throws {
        let fixture = try setUp(), context = fixture.context, store = fixture.store
        let leo = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Leo", lastName: "Katz", dateStarted: try CoreDataTestHelpers.day("2026-10-01")
        )
        #expect(throws: AttendanceMarkRefusal.notOnRoll(.notStarted)) {
            try store.mark(student: leo, status: .present, on: try CoreDataTestHelpers.day("2026-09-14"))
        }
    }

    @Test("A day off is refused unless confirmed")
    func dayOffNeedsConfirming() throws {
        let fixture = try setUp(), context = fixture.context, store = fixture.store, maya = fixture.maya
        let saturday = try CoreDataTestHelpers.day("2026-09-19")
        #expect(throws: AttendanceMarkRefusal.dayOff) {
            try store.mark(student: maya, status: .present, on: saturday)
        }
        #expect(allRecords(context).isEmpty)
        let outcome = try store.mark(student: maya, status: .present, on: saturday, dayOffConfirmed: true)
        #expect(outcome.record?.status == .present)
    }

    @Test("Claude marks a day off only with confirm_day_off")
    func claudeConfirmsADayOff() async throws {
        let fixture = try setUp(), context = fixture.context, maya = fixture.maya
        let tool = try #require(MCPNotebookTools.makeTools(context: { context }).first { $0.name == "mark_attendance" })
        await #expect(throws: MCPToolError.self) {
            _ = try await tool.handler([
                "student_name": .string("Maya"), "status": .string("present"), "date": .string("2026-09-19")
            ])
        }
        #expect(allRecords(context).isEmpty)
        _ = try await tool.handler([
            "student_name": .string("Maya"), "status": .string("present"), "date": .string("2026-09-19"),
            "confirm_day_off": .bool(true)
        ])
        #expect(allRecords(context).first { $0.studentID == maya.cloudKitKey }?.status == .present)
    }

    @Test("A locked day is refused")
    func lockedDayIsRefused() throws {
        let fixture = try setUp(), context = fixture.context, store = fixture.store, maya = fixture.maya
        let day = try CoreDataTestHelpers.day("2026-09-14")
        let lock = CDAttendanceDayLock(context: context)
        lock.date = day
        try context.save()
        #expect(throws: AttendanceMarkRefusal.locked) {
            try store.mark(student: maya, status: .present, on: day)
        }
    }

    @Test("The absence report counts school days only and gives the days enrolled")
    func reportCountsSchoolDaysOnly() throws {
        let fixture = try setUp(), context = fixture.context, maya = fixture.maya
        let monday = try CoreDataTestHelpers.day("2026-09-14")
        for offset in 0..<5 {
            let record = CDAttendanceRecord(context: context)
            record.studentID = maya.cloudKitKey
            record.date = AppCalendar.addingDays(offset, to: monday)
            record.status = offset == 0 ? .present : .absent
        }
        let storm = CDNonSchoolDay(context: context)
        storm.date = AppCalendar.addingDays(4, to: monday)
        try context.save()

        let rows = AttendanceStatusReport.rows(
            config: .absence, students: [maya], in: monday...AppCalendar.addingDays(6, to: monday), context: context
        )
        let row = try #require(rows.first)
        #expect(row.count == 3)
        #expect(row.daysEnrolled == 4)
    }

    @Test("A mark after her last day doesn't count, nor does the day count as enrolled")
    func tallyStopsAtTheLastDay() throws {
        let context = try setUp().context
        let monday = try CoreDataTestHelpers.day("2026-09-14")
        let rivka = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Gold", enrollmentStatus: .withdrawn, dateWithdrawn: monday
        )
        for offset in 0..<2 {
            let record = CDAttendanceRecord(context: context)
            record.studentID = rivka.cloudKitKey
            record.date = AppCalendar.addingDays(offset, to: monday)
            record.status = .absent
        }
        try context.save()
        let tally = AttendanceTallies.tallies(
            records: allRecords(context).deduplicatedPerStudentDay(), students: [rivka],
            days: AttendanceTallies.days(in: monday...AppCalendar.addingDays(1, to: monday)), daysOff: []
        )
        #expect(tally[rivka.cloudKitKey] == AttendanceTally(daysEnrolled: 1, absent: 1))
    }

    @Test("Turning a marked day into a day off over Claude says the marks stop counting")
    func dayOffWithMarksSaysSo() async throws {
        let fixture = try setUp(), context = fixture.context, store = fixture.store, maya = fixture.maya
        let day = try CoreDataTestHelpers.day("2026-09-14")
        try store.mark(student: maya, status: .present, on: day)
        try context.save()
        let tool = try #require(MCPNotebookTools.makeTools(context: { context }).first { $0.name == "set_school_days" })
        let reply = try await tool.handler(["date": .string("2026-09-14"), "in_session": .bool(false)])
        #expect(reply.contains("Attendance was already marked on"))
        #expect(reply.contains("1 child"))
    }

    // MARK: - Paired fields

    @Test("normalize leaves every state the store writes alone")
    func normalizeKeepsWhatTheStoreWrites() throws {
        let fixture = try setUp(), context = fixture.context, store = fixture.store, maya = fixture.maya
        let today = AppCalendar.startOfDay(Date())
        let leo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leo", lastName: "Katz")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let ahead = AppCalendar.addingDays(7, to: today)

        // Back in Class: late, out and back, with a pickup that came and went.
        let trip = try #require(try store.mark(student: maya, status: .tardy, on: today, dayOffConfirmed: true).record)
        store.updateLeavesAt(trip, to: today.addingTimeInterval(13 * 3_600))
        try store.mark(student: maya, status: .leftEarly, on: today, dayOffConfirmed: true)
        store.markBack(trip)
        // Close Arrival's automatic absence, with a planned pickup.
        let closed = try #require(try store.markUnmarkedAbsent(for: today, students: [leo]).first)
        store.updateLeavesAt(closed, to: today.addingTimeInterval(14 * 3_600))
        // An absence marked ahead, with its reason and no time; a note.
        let away = try #require(
            try store.mark(student: ora, status: .absent, reason: .vacation, on: ahead, dayOffConfirmed: true).record
        )
        store.updateNote(away, to: "Grandparents")

        for record in [trip, closed, away] {
            #expect(record.hasMismatchedFields == false)
            #expect(record.normalize() == false)
        }
        #expect(trip.returnedAt != nil && trip.leftAt != nil)
        #expect(AttendanceDeduplication.isAutomaticAbsence(closed))
        #expect(away.absenceReason == .vacation && away.markedAt == nil)
    }

    @Test("normalize clears details that don't fit the mark, and leaves an unknown status alone")
    func normalizeFixesOddPairs() throws {
        let fixture = try setUp(), context = fixture.context, maya = fixture.maya
        func record(_ statusRaw: String) -> CDAttendanceRecord {
            let record = CDAttendanceRecord(context: context)
            record.studentID = maya.cloudKitKey
            record.date = Date()
            record.statusRaw = statusRaw
            return record
        }
        let presentSick = record(AttendanceStatus.present.rawValue)
        presentSick.absenceReasonRaw = AbsenceReason.sick.rawValue
        let absentBack = record(AttendanceStatus.absent.rawValue)
        absentBack.leftAt = Date()
        absentBack.returnedAt = Date()
        let leftFromAbsent = record(AttendanceStatus.leftEarly.rawValue)
        leftFromAbsent.statusBeforeLeavingRaw = AttendanceStatus.absent.rawValue
        let blankTimed = record(AttendanceStatus.unmarked.rawValue)
        blankTimed.markedAt = Date()
        blankTimed.leavesAt = Date()
        let newer = record("napping")
        newer.absenceReasonRaw = AbsenceReason.sick.rawValue

        #expect(CDAttendanceRecord.normalizeAll(in: context) == 4)
        #expect(presentSick.absenceReason == .none)
        #expect(absentBack.leftAt == nil && absentBack.returnedAt == nil)
        #expect(leftFromAbsent.statusBeforeLeavingRaw == nil)
        #expect(blankTimed.markedAt == nil)
        #expect(blankTimed.leavesAt != nil)
        #expect(newer.absenceReasonRaw == AbsenceReason.sick.rawValue)
    }

    @Test("data_checks lists attendance whose details don't fit the mark")
    func dataChecksListsOddPairs() async throws {
        let fixture = try setUp(), context = fixture.context, maya = fixture.maya
        let odd = CDAttendanceRecord(context: context)
        odd.studentID = maya.cloudKitKey
        odd.date = try CoreDataTestHelpers.day("2026-09-14")
        odd.statusRaw = AttendanceStatus.present.rawValue
        odd.absenceReasonRaw = AbsenceReason.sick.rawValue
        try context.save()
        let tool = try #require(MCPNotebookTools.makeTools(context: { context }).first { $0.name == "data_checks" })
        let reply = try await tool.handler(["check": .string("attendance_pairs")])
        #expect(reply.contains("Attendance marks with details that don't fit the mark: 1."))
        #expect(reply.contains("Maya Stein, 2026-09-14: present"))
    }
}
