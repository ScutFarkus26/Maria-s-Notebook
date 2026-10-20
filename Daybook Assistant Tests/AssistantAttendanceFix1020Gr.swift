import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Daybook Assistant bug hunt 2026-10-20, #1, #2 and #5: the grid opening on
// yesterday the next morning, and the Late phase slipping back to Arrival
// once Close Arrival's absences were resolved on a phone that didn't close
// arrival (or staying Late on one that did, after another phone's Undo).
@Suite("Assistant grid: the day and the Late phase (Fix1020 Gr)")
@MainActor
struct AssistantAttendanceFix1020GrTests {

    private let fixture: AssistantGridFixture
    private var monday: Date { fixture.monday }
    private var context: NSManagedObjectContext { fixture.context }
    private var guide: CDAttendanceStore { fixture.guide }

    init() throws {
        fixture = try AssistantGridFixture()
    }

    private func row(_ first: String, in model: AssistantAttendanceViewModel) throws -> AssistantGridFixture.Model.Row {
        try fixture.row(first, in: model)
    }

    private func record(of student: CDStudent) throws -> CDAttendanceRecord {
        try fixture.record(of: student, on: monday)
    }

    // MARK: - #1 The next morning opens on today

    @Test("Back after a night away (tab or app), the grid moves to today, wherever it was left")
    func nextMorningOpensOnToday() throws {
        fixture.classOf(["Ari"])
        let clock = AssistantGridFixture.Clock(monday.addingTimeInterval(15 * 3_600))
        let model = fixture.model(clock: clock)
        #expect(model.isToday)

        // Left on Monday overnight (on Restock, say): Tuesday's first look is Tuesday.
        clock.now = monday.addingTimeInterval(32 * 3_600)
        model.reloadAfterAway()
        #expect(model.date == Calendar.current.date(byAdding: .day, value: 1, to: monday))
        #expect(model.isToday)
    }

    @Test("Within the day, a day she picked stays; after a night away, today")
    func pickedDayStaysUntilTheNextDay() throws {
        fixture.classOf(["Ari"])
        let clock = AssistantGridFixture.Clock(monday.addingTimeInterval(10 * 3_600))
        let model = fixture.model(clock: clock)
        let friday = try AssistantTestSupport.day("2031-01-03")
        model.load(friday)

        clock.now = monday.addingTimeInterval(14 * 3_600)
        model.reloadAfterAway()
        #expect(model.date == friday)

        clock.now = monday.addingTimeInterval(32 * 3_600)
        model.reloadAfterAway()
        #expect(model.isToday)
    }

    // MARK: - #2 and #5 Late holds until an Undo

    @Test("Closed on the guide's device: Late holds here once its absences are resolved")
    func lateHoldsAfterTheAbsencesAreResolved() throws {
        let kids = fixture.classOf(["Ari", "Bea", "Maya"])
        let (ari, bea, maya) = (kids[0], kids[1], kids[2])
        let phone = fixture.model()
        #expect(guide.updateStatus(try #require(try guide.ensureRecord(for: bea, on: monday)), to: .present))
        #expect(try guide.markUnmarkedAbsent(for: monday, students: [ari, maya]).count == 2)
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .late)

        // Maya came in late; Ari's absence is Sick: no automatic absence is left.
        #expect(guide.updateStatus(try record(of: maya), to: .tardy))
        #expect(guide.updateAbsenceReason(try record(of: ari), to: .sick))
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .late)
        #expect(phone.statusAfterTap(for: try row("Maya", in: phone)) == .absent)
    }

    @Test("The store reads the day as closed the same way, for Siri and the notebook")
    func storeReadsTheSameRule() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        let defaults = AssistantTestSupport.makeDefaults()
        let phone = CDAttendanceStore(context: context, role: .assistant)
        #expect(try guide.markUnmarkedAbsent(for: monday, students: kids).count == 2)
        #expect(context.safeSave())
        #expect(try phone.arrivalClosed(on: monday, defaults: defaults))

        for child in kids { #expect(guide.updateStatus(try record(of: child), to: .tardy)) }
        #expect(context.safeSave())
        #expect(try phone.arrivalClosed(on: monday, defaults: defaults))
        #expect(AttendanceLatePhase.isLate(
            on: monday, closedAnywhere: (try? phone.arrivalClosed(on: monday, defaults: defaults)) == true,
            defaults: defaults
        ))
    }

    @Test("Seen closed, then undone on another device: back to Arrival")
    func undoneElsewhereReopens() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        let phone = fixture.model()
        #expect(try guide.markUnmarkedAbsent(for: monday, students: kids).count == 2)
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .late)

        for child in kids { #expect(guide.undoAutomaticAbsence(try record(of: child))) }
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .arrival)
        #expect(phone.statusAfterTap(for: try row("Ari", in: phone)) == .present)
    }

    @Test("Two phones close arrival, one taps Undo: the other goes back to Arrival too")
    func undoOnTheOtherPhoneReopensThisOne() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        let phone = fixture.model()
        #expect(phone.beginLate() == 2)
        #expect(phone.phase == .late)

        // The other phone's Undo of its own close clears every automatic
        // absence on those children, this phone's copies included.
        let other = CDAttendanceStore(context: context, role: .assistant)
        for child in kids { #expect(other.undoAutomaticAbsence(try record(of: child))) }
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .arrival)
        #expect(phone.statusAfterTap(for: try row("Maya", in: phone)) == .present)
    }

    // Both changes land before the phone's next look; a phone looking in
    // between is AssistantFix1020RoundA2's.
    @Test("Clearing one remembered child's mark isn't an Undo: Late holds")
    func clearingOneIsNotAnUndo() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        let phone = fixture.model()
        #expect(try guide.markUnmarkedAbsent(for: monday, students: kids).count == 2)
        #expect(context.safeSave())
        phone.load()

        #expect(guide.unmark(try record(of: kids[0])))
        #expect(guide.updateAbsenceReason(try record(of: kids[1]), to: .sick))
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .late)
    }

    // Leaving the class (`forget`) is tested without a reopen in
    // AssistantFix1020RoundA2: after one it passed whatever forget did
    // (review of the 2026-10-20 fixes, (a) 9).
    @Test("A reopen here still wins")
    func reopenWins() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        let defaults = AssistantTestSupport.makeDefaults()
        let phone = fixture.model(defaults: defaults)
        #expect(try guide.markUnmarkedAbsent(for: monday, students: kids).count == 2)
        #expect(context.safeSave())
        phone.load()
        for child in kids { #expect(guide.updateStatus(try record(of: child), to: .tardy)) }
        #expect(context.safeSave())
        phone.load()
        #expect(phone.phase == .late)

        phone.returnToArrival()
        phone.load()
        #expect(phone.phase == .arrival)
    }
}

// MARK: - #2 Siri's "here" goes by the same rule

extension AssistantSiriTests {

    @Test("Siri's here marks late once the guide's Close Arrival absences are all resolved (Fix1020 Gr)")
    func siriHereAfterResolvedAbsences() throws {
        let day = try AssistantTestSupport.day("2031-01-06")
        defer {
            SiriAttendanceChange.forget()
            AttendanceLatePhase.setLate(false, on: day)
        }
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        #expect(context.safeSave())
        let guide = CDAttendanceStore(context: context, role: .leadGuide)
        let phone = CDAttendanceStore(context: context, role: .assistant)
        let closed = try guide.markUnmarkedAbsent(for: day, students: [ari, maya])
        #expect(closed.count == 2)
        #expect(context.safeSave())
        #expect(SiriHost.statusForHere(on: day, store: phone) == .tardy)

        for record in closed { #expect(guide.updateStatus(record, to: .tardy)) }
        #expect(context.safeSave())
        #expect(SiriHost.statusForHere(on: day, store: phone) == .tardy)
    }
}
