import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The grid's Close Arrival, its Undo and Reopen, a child's duplicate records,
// days off and who made a mark: the attendance findings of the 2026-10-04
// bug hunt (Phase 1 of docs/Plans/Plan - Daybook Assistant bug fixes.md).
@Suite("Assistant grid: Close Arrival, copies and days off")
@MainActor
struct AssistantArrivalFixesTests {

    typealias Model = AssistantAttendanceViewModel

    /// A record of `student`'s on `day` made on another device, as if synced in.
    @discardableResult
    private func copy(
        of student: CDStudent,
        on day: Date,
        _ status: AttendanceStatus,
        automatic: Bool = false,
        secondsAgo: TimeInterval,
        in context: NSManagedObjectContext
    ) throws -> CDAttendanceRecord {
        let record = CDAttendanceRecord(context: context)
        record.studentID = try #require(student.id?.uuidString)
        record.date = day
        record.status = status
        if automatic { record.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw }
        record.recordedBy = CDClassroomMembership.ClassroomRole.leadGuide.rawValue
        record.modifiedAt = Date().addingTimeInterval(-secondsAgo)
        return record
    }

    // Step 2: Undo reopened arrival on purpose, so a Close Arrival the guide
    // made afterwards was ignored on this phone.
    @Test("After Close Arrival's Undo, the guide closing arrival later puts this phone in Late")
    func undoFollowsTheRecords() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let defaults = AssistantTestSupport.makeDefaults()
        let model = AssistantTestSupport.viewModel(stack, defaults: defaults)
        #expect(model.beginLate() == 2)
        model.returnToArrival(undo: true)
        #expect(model.phase == .arrival)

        let guide = CDAttendanceStore(context: context, role: .leadGuide)
        #expect(try guide.markUnmarkedAbsent(for: model.date, students: [ari, maya]).count == 2)
        #expect(context.safeSave())
        model.load()
        #expect(model.phase == .late)

        // Reopen Arrival is still on purpose, and holds.
        model.returnToArrival()
        model.load()
        #expect(model.phase == .arrival)
    }

    // Step 1: another device's Close Arrival on the same child, before they
    // synced, kept the child absent and the day closed after the Undo.
    @Test("Close Arrival's Undo clears another device's automatic absence on the same child")
    func undoClearsAutomaticCopies() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let model = AssistantTestSupport.viewModel(stack)
        #expect(model.beginLate() == 1)
        try copy(of: ari, on: model.date, .absent, automatic: true, secondsAgo: 60, in: context)
        #expect(context.safeSave())

        model.returnToArrival(undo: true)
        model.load()
        #expect(model.rows.first?.status == .unmarked)
        #expect(model.phase == .arrival)
        #expect(try !CDAttendanceStore(context: context, role: .assistant).arrivalClosed(on: model.date))
    }

    // Step 3 (Sample Class walk): with everyone marked, Reopen Arrival left
    // no control at all, so there was no way back to Late.
    @Test("After Reopen Arrival with nobody unmarked, Close Arrival is still the way back to Late")
    func reopenThenBackToLate() throws {
        let stack = try AssistantTestSupport.makeStack()
        for (first, last) in [("Ari", "Cedar"), ("Maya", "Stone")] {
            AssistantTestSupport.student(first, last, in: stack.viewContext)
        }
        let model = AssistantTestSupport.viewModel(stack)
        model.tap(try #require(model.rows.first { $0.student.firstName == "Ari" }))
        #expect(model.beginLate() == 1)

        model.returnToArrival()
        #expect(model.phase == .arrival && model.unmarkedNames.isEmpty)
        #expect(model.showsArrivalControl)
        model.load()
        #expect(model.showsArrivalControl)

        #expect(model.beginLate() == 0)
        #expect(model.phase == .late)

        // Once Maya is marked in by hand, nothing automatic is left to go back to.
        model.returnToArrival()
        model.tap(try #require(model.rows.first { $0.student.firstName == "Maya" }))
        #expect(!model.showsArrivalControl)
    }

    // Step 5: a CloudKit duplicate still marked won the child straight back.
    @Test("Clearing a mark clears it on the day's duplicate records too, keeping their notes")
    func unmarkClearsCopies() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let model = AssistantTestSupport.viewModel(stack)
        try copy(of: ari, on: model.date, .present, secondsAgo: 120, in: context).note = "Dentist at 2"
        try copy(of: ari, on: model.date, .tardy, secondsAgo: 60, in: context)
        #expect(context.safeSave())
        model.load()
        #expect(model.rows.first?.status == .tardy)

        model.setStatus(.unmarked, for: try #require(model.rows.first))
        model.load()
        #expect(model.rows.first?.status == .unmarked)
        let records = context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.status == .unmarked })
        #expect(records.contains { $0.note == "Dentist at 2" })
    }

    // Step 6: Absent › No Reason on Close Arrival's absence compared equal
    // (the marker reads as no reason), so it took the marker off without
    // stamping the change as hers.
    @Test("Absent, no reason, on Close Arrival's absence makes it hers")
    func noReasonOnAutomaticAbsence() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let model = AssistantTestSupport.viewModel(stack)
        let guide = CDAttendanceStore(context: context, role: .leadGuide)
        let record = try #require(try guide.markUnmarkedAbsent(for: model.date, students: [ari]).first)
        #expect(context.safeSave())
        model.load()

        model.markAbsent(reason: .none, for: try #require(model.rows.first))
        #expect(!AttendanceDeduplication.isAutomaticAbsence(record))
        #expect(record.recordedBy == CDClassroomMembership.ClassroomRole.assistant.rawValue)
        #expect(model.rows.first?.recordedBy == CDClassroomMembership.ClassroomRole.assistant.rawValue)
    }

    // Step 7: a day off saved at another time than midnight (an older build,
    // another time zone) read as a weekend.
    @Test("A day off saved at another time of day still shows as the guide's day off")
    func dayOffAtAnotherTime() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        let wednesday = try AssistantTestSupport.day("2026-10-07")
        let holiday = CDNonSchoolDay(context: context)
        holiday.date = wednesday.addingTimeInterval(9 * 3_600)
        holiday.reason = "Staff day"
        #expect(context.safeSave())

        let model = AssistantTestSupport.viewModel(stack, on: wednesday)
        #expect(model.dayOff == .holiday("Staff day"))
    }

    // Step 9: the guide locked the day after it loaded here; Close Arrival
    // marked no one but still switched to Late.
    @Test("Close Arrival on a day locked since it loaded changes nothing, and the lock shows")
    func closeOnDayLockedSinceLoad() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        let defaults = AssistantTestSupport.makeDefaults()
        let model = AssistantTestSupport.viewModel(stack, defaults: defaults)
        #expect(model.canMark)
        #expect(AttendanceDayLocks.setLocked(true, for: model.date, role: .leadGuide, in: context))

        #expect(model.beginLate() == 0)
        #expect(model.phase == .arrival)
        #expect(!AttendanceLatePhase.isLate(on: model.date, defaults: defaults))
        #expect(model.isLocked)
        #expect(!model.canMark)
    }

    // Step 16 (Sample Class walk): her own mark, from a phone with no record
    // name and no name set, read "by an assistant".
    @Test("Her own mark with no record name or name set reads as hers")
    func ownMarkWithoutIdentity() throws {
        let stack = try AssistantTestSupport.makeStack()
        let student = AssistantTestSupport.student("Ari", "Cedar", in: stack.viewContext)
        let record = CDAttendanceRecord(context: stack.viewContext)
        record.studentID = try #require(student.id?.uuidString)
        record.date = Calendar.current.startOfDay(for: Date())
        record.status = .present
        record.recordedBy = CDClassroomMembership.ClassroomRole.assistant.rawValue
        let mine = Model.Row(student: student, record: record, shortName: "Ari", day: Date())
        #expect(Model.markerName(for: mine, myRecordName: nil, myName: nil, guideName: nil) == "you")
        // The guide's notebook doesn't take an unnamed assistant's mark for its own.
        let onTheMac = AttendanceRules.markerName(for: mine, myRecordName: nil, myName: nil, guideName: "you")
        #expect(onTheMac == "an assistant")

        record.recordedByID = "another phone"
        let theirs = Model.Row(student: student, record: record, shortName: "Ari", day: Date())
        #expect(Model.markerName(for: theirs, myRecordName: nil, myName: nil, guideName: nil) == "an assistant")
    }
}
