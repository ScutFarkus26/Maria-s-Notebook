import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The fix round after review (a) of the Assistant's 2026-10-20 fixes, items
// 2, 3 and 9 (plan "Daybook Assistant bug hunt 2026-10-20 fixes", Phase 2):
// every device remembers the same children for a closed day (everyone seen
// carrying Close Arrival's absence, and everyone seen marked Late at or
// after the close), Reopen keeps them and the bar offers the way back to
// Late, and leaving the class forgets a day seen closed.
@Suite("Assistant fixes 2026-10-20: review (a) round, the Late rule")
@MainActor
struct AssistantFix1020RoundA2 {

    private let fixture: AssistantGridFixture
    private var monday: Date { fixture.monday }
    private var context: NSManagedObjectContext { fixture.context }
    private var guide: CDAttendanceStore { fixture.guide }
    /// What the guide's Mac remembers.
    private let mac = AssistantTestSupport.makeDefaults()
    /// What the phone remembers.
    private let phoneDefaults = AssistantTestSupport.makeDefaults()

    init() throws {
        fixture = try AssistantGridFixture()
    }

    /// `hour`:`minute` on the Monday.
    private func at(_ hour: Int, _ minute: Int) -> Date {
        monday.addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    private func record(of student: CDStudent) throws -> CDAttendanceRecord {
        try fixture.record(of: student, on: monday)
    }

    /// The guide's Close Arrival on the Mac at 9:00: everyone in `kids` still
    /// unmarked marked absent by it, timed as on the day (the store times
    /// only today's marks, and the Monday is in 2031), and remembered by the
    /// Mac as the notebook's Close Arrival does.
    private func macCloses(_ kids: [CDStudent]) throws {
        let closed = try guide.markUnmarkedAbsent(for: monday, students: kids)
        for record in closed { record.markedAt = at(9, 0) }
        #expect(context.safeSave())
        AttendanceLatePhase.setLate(true, on: monday, defaults: mac)
        AttendanceLatePhase.closedAnywhere(on: monday, records: closed, defaults: mac)
    }

    /// `child` marked Late on the Mac at `time`.
    private func late(_ child: CDStudent, at time: Date) throws {
        let record = try #require(try guide.ensureRecord(for: child, on: monday))
        #expect(guide.updateStatus(record, to: .tardy))
        record.markedAt = time
        #expect(context.safeSave())
    }

    private func phone() -> AssistantAttendanceViewModel {
        fixture.model(defaults: phoneDefaults)
    }

    /// Whether the phone's store (Siri's reading) sees the day closed.
    private func phoneStoreReadsClosed() throws -> Bool {
        try CDAttendanceStore(context: context, role: .assistant).arrivalClosed(on: monday, defaults: phoneDefaults)
    }

    // MARK: - 2: the same memory on every device

    @Test("The phone looks between the changes: clearing the last absence keeps Late, as on the Mac (2)")
    func phoneLookingBetweenTheChangesStaysLate() throws {
        let kids = fixture.classOf(["Ari", "Ben", "Cal"])
        try macCloses(kids)
        try late(kids[0], at: at(9, 10))
        try late(kids[1], at: at(9, 15))
        // The phone's first look: only Cal still carries the absence.
        let phone = phone()
        #expect(phone.phase == .late)

        #expect(guide.unmark(try record(of: kids[2])))
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .late, "Ari and Ben came in after the close")
        #expect(phone.statusAfterTap(for: try fixture.row("Cal", in: phone)) == .tardy)
        #expect(try phoneStoreReadsClosed())
        #expect(try guide.arrivalClosed(on: monday, defaults: mac), "the Mac reads the day the same way")
    }

    @Test("A child who came in late after the close and went home early still counts (2)")
    func lateThenLeftEarlyCounts() throws {
        let kids = fixture.classOf(["Ari", "Cal"])
        try macCloses(kids)
        try late(kids[0], at: at(9, 10))
        #expect(guide.updateStatus(try record(of: kids[0]), to: .leftEarly))
        #expect(context.safeSave())
        let phone = phone()
        #expect(phone.phase == .late)

        #expect(guide.unmark(try record(of: kids[1])))
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .late)
    }

    @Test("Undo right after the close: Arrival on a phone that saw it; a Late from the menu later doesn't close it (2)")
    func undoRightAfterTheClose() throws {
        let kids = fixture.classOf(["Ari", "Ben"])
        try macCloses(kids)
        let phone = phone()
        #expect(phone.phase == .late)

        for child in kids { #expect(guide.undoAutomaticAbsence(try record(of: child))) }
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .arrival)
        #expect(phone.statusAfterTap(for: try fixture.row("Ari", in: phone)) == .present)

        // Arrival is open again: Ari marked Late from the menu at 9:20 is
        // just a mark, not a close.
        try late(kids[0], at: at(9, 20))
        phone.load()
        #expect(phone.phase == .arrival)
        #expect(try !phoneStoreReadsClosed())
    }

    @Test("A child marked Late from the menu before the close doesn't keep the day closed after an Undo (2)")
    func lateBeforeTheCloseDoesNotBlockAnUndo() throws {
        let kids = fixture.classOf(["Ari", "Ben", "Dan"])
        try late(kids[2], at: at(8, 50))
        try macCloses(kids)
        let phone = phone()
        #expect(phone.phase == .late)
        // A second look, still before the Undo, sees Dan's 8:50 Late again.
        phone.load()
        #expect(phone.phase == .late)

        for child in kids.prefix(2) { #expect(guide.undoAutomaticAbsence(try record(of: child))) }
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .arrival)
        #expect(try !phoneStoreReadsClosed())
    }

    // MARK: - 3: Reopen and the way back to Late

    @Test("Reopen keeps who the close took in, and the bar offers the way back to Late (3)")
    func reopenThenBackToLate() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        try macCloses(kids)
        let phone = phone()
        try late(kids[0], at: at(9, 10))
        #expect(guide.updateAbsenceReason(try record(of: kids[1]), to: .sick))
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .late)

        phone.returnToArrival()
        phone.load()
        #expect(phone.phase == .arrival, "a reopen here still wins")
        #expect(phone.unmarkedCount == 0)
        #expect(phone.showsArrivalControl, "the way back to Late, with nobody to mark")

        #expect(phone.beginLate() == 0)
        #expect(phone.phase == .late)
        phone.load()
        #expect(phone.phase == .late)
        #expect(phone.statusAfterTap(for: try fixture.row("Maya", in: phone)) == .tardy)
    }

    @Test("After a reopen, an Undo on the Mac still puts the phone back to following the records (3)")
    func reopenThenUndoElsewhere() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        try macCloses(kids)
        let phone = phone()
        phone.returnToArrival()
        phone.load()
        #expect(phone.showsArrivalControl)

        for child in kids { #expect(guide.undoAutomaticAbsence(try record(of: child))) }
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .arrival)
        #expect(try !phoneStoreReadsClosed())

        // Forgotten, reopen and all: the guide's next Close Arrival counts here.
        try macCloses(kids)
        phone.load()
        #expect(phone.phase == .late)
    }

    // MARK: - 9: leaving the class forgets a day seen closed

    @Test("Leaving the class forgets a day seen closed: Arrival, without a reopen (9)")
    func forgetClearsASeenClosedDay() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        try macCloses(kids)
        let phone = phone()
        for child in kids { try late(child, at: at(9, 10)) }
        phone.load()
        #expect(phone.phase == .late)
        #expect(try phoneStoreReadsClosed())

        AttendanceLatePhase.forget(defaults: phoneDefaults)
        phone.load()
        #expect(phone.phase == .arrival)
        #expect(fixture.model(defaults: phoneDefaults).phase == .arrival)
    }
}
