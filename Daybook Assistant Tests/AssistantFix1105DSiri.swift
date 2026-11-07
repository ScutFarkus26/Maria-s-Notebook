import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The review of the 2026-11-05 fixes, Siri's side (`AssistantFix1105D` has
// the rest): its Undo waits out a Close Arrival send under way (W1), and its
// Close Arrival says when part of the class went (W7), on the real sync.
// Tests set the engine's `closeArrivalSendUnderWay` by hand, as the engine
// sets it during a run.

/// Siri's Close Arrival on a class of two: Ari in already, Maya marked absent.
@MainActor
struct Fix1105DClosedClass {
    let siri: SiriAttendance
    let day: Date
    let maya: CDStudent

    init() async throws {
        day = try AssistantTestSupport.day("2031-01-20")
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let attendance = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try attendance.ensureRecord(for: ari, on: day))
        #expect(attendance.updateStatus(record, to: .present))
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(.parentLocker, in: context)
        siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 1)
    }

    /// Siri's memories of the close, cleared after each test.
    func forget() {
        SiriAttendanceChange.forget()
        AttendanceLatePhase.setLate(false, on: day)
    }

    /// `siri`, with its Undo reading `sync` and waiting at most `wait`.
    func undoing(with sync: ParentLockerSync, waitingAtMost wait: Duration) -> SiriAttendance {
        var undoing = siri
        undoing.parentLocker = { sync }
        undoing.parentLockerWait = wait
        return undoing
    }

    /// The class's sync over `transport`, as the Assistant makes it, signed
    /// in, recording each send in `recorded`.
    func sync(over transport: any ParentLockerTransport, recorded: Fix1105Count = Fix1105Count()) -> ParentLockerSync {
        var dependencies = ParentLockerSync.Dependencies(store: ParentLockerCoreDataStore(
            context: siri.context, sendRecorded: { _ in recorded.value += 1 }, fixedRole: .assistant
        ))
        dependencies.secrets = FixRoundSecrets()
        dependencies.makeTransport = { _, _, _ in transport }
        dependencies.clock = FixRoundClock(siri.today)
        dependencies.policy = .live
        dependencies.unsent = ParentLockerMemoryUnsentStore()
        dependencies.refusals = ParentLockerMemoryRefusalStore()
        dependencies.importsExpected = false
        let sync = ParentLockerSync(dependencies: dependencies)
        sync.refreshSignIn()
        return sync
    }
}

// In `AssistantSiriTests`, so they run one at a time with it: closing
// arrival writes the app's own Late and Siri memories.
extension AssistantSiriTests {

    private static func fix1105DEventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private static func message(_ error: any Error) -> String? {
        (error as? SiriAttendanceError).map { String(localized: $0.localizedStringResource) }
    }

    // MARK: - W1: Siri's Undo while Close Arrival's send is under way

    @Test("W1: Siri waits at most 8 s for Close Arrival's send before undoing it")
    func siriUndoWaitIsEightSeconds() {
        #expect(SiriAttendance.parentLockerWait == .seconds(8))
        #expect(AssistantSiriCommands.siriSendWait == SiriAttendance.parentLockerWait)
    }

    @Test("W1: Siri's Undo while the send is still going waits for it, then says ParentLocker keeps the absences",
          .timeLimit(.minutes(1)))
    func siriUndoWaitsOutTheSend() async throws {
        let closed = try await Fix1105DClosedClass()
        defer { closed.forget() }
        let site = FixRoundSite()
        let gate = Fix1105SaveGate()
        let recorded = Fix1105Count()
        let sync = closed.sync(
            over: Fix1105SlowTransport(inner: FixRoundTransport(site: site), gate: gate), recorded: recorded
        )
        #expect(await AssistantSiriCommands.sendAfterClose(closed.siri, marked: 1, sync: sync, waitsAtMost: .milliseconds(100))
            == .onItsWay)
        #expect(await Self.fix1105DEventually { gate.waiting })
        // As the engine says it from the moment the send was taken to run.
        sync.closeArrivalSendUnderWay = true

        let undoing = closed.undoing(with: sync, waitingAtMost: .seconds(5))
        let undo = Task { try await undoing.undoLast() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(try closed.siri.status(of: closed.maya) == .absent, "nothing is undone while the send is under way")
        #expect(AttendanceLatePhase.isLate(on: closed.day))

        // The save lands, the day is recorded, and the run ends.
        gate.open()
        #expect(await Self.fix1105DEventually { recorded.value > 0 })
        sync.closeArrivalSendUnderWay = false
        let said = try await undo.value
        #expect(said == "Done. Arrival is open again. " + SiriAttendanceChange.parentLockerKeepsAbsences)
        #expect(site.saves.first?.entries.count == 2, "the whole class went, Maya's absence with it")
        #expect(try closed.siri.status(of: closed.maya) == .unmarked, "undone here once the send had ended")
    }

    @Test("W1: still going after the wait, Siri's Undo leaves everything as it was and says to try again",
          .timeLimit(.minutes(1)))
    func siriUndoRefusedWhileStillUnderWay() async throws {
        let closed = try await Fix1105DClosedClass()
        defer { closed.forget() }
        let (sync, _) = FixRoundSite().sync(on: closed.siri.context, at: closed.siri.today)
        sync.closeArrivalSendUnderWay = true
        let undoing = closed.undoing(with: sync, waitingAtMost: .milliseconds(200))

        await #expect {
            try await undoing.undoLast()
        } throws: { error in
            Self.message(error) == "Attendance is going to ParentLocker right now, so it can't be undone yet. "
                + "Try again in a moment."
        }
        #expect(try closed.siri.status(of: closed.maya) == .absent, "nothing undone")
        #expect(AttendanceLatePhase.isLate(on: closed.day), "arrival is still closed")
        #expect(SiriAttendanceChange.last() != nil, "kept, so asking again can undo it")

        // The run ended with nothing gone: asking again undoes it.
        sync.closeArrivalSendUnderWay = false
        #expect(try await undoing.undoLast() == "Done. Arrival is open again.")
        #expect(try closed.siri.status(of: closed.maya) == .unmarked)
    }

    @Test("W1: an Undo after part of the class went says ParentLocker may keep those absences",
          .timeLimit(.minutes(1)))
    func siriUndoAfterPartWent() async throws {
        let closed = try await Fix1105DClosedClass()
        defer { closed.forget() }
        let (sync, _) = FixRoundSite().sync(on: closed.siri.context, at: closed.siri.today)
        sync.closeArrivalSendUnderWay = true
        let undoing = closed.undoing(with: sync, waitingAtMost: .seconds(5))
        let undo = Task { try await undoing.undoLast() }
        try await Task.sleep(for: .milliseconds(100))
        // One class saved and the other couldn't be reached: a retry waits.
        sync.status = ParentLockerStatus(state: .retrying)
        sync.closeArrivalSendUnsent = false
        sync.closeArrivalSendUnderWay = false
        #expect(try await undo.value == "Done. Arrival is open again. " + SiriAttendance.parentLockerMayKeepAbsences)
    }

    @Test("W1: an Undo of one child's mark doesn't wait for Close Arrival's send", .timeLimit(.minutes(1)))
    func siriUndoOfAMarkDoesNotWait() async throws {
        let closed = try await Fix1105DClosedClass()
        defer { closed.forget() }
        let (sync, _) = FixRoundSite().sync(on: closed.siri.context, at: closed.siri.today)
        sync.closeArrivalSendUnderWay = true
        let undoing = closed.undoing(with: sync, waitingAtMost: .seconds(30))
        _ = try await undoing.markHere(closed.maya)
        let started = ContinuousClock.now
        #expect(try await undoing.undoLast() == "Done. Maya isn't marked late anymore.")
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    // MARK: - W7 on the real sync: part of the class went

    @Test("W7: Siri's Close Arrival after one class went and the other couldn't be read says part of it went",
          .timeLimit(.minutes(1)))
    func siriSaysPartWent() async throws {
        let closed = try await Fix1105DClosedClass()
        defer { closed.forget() }
        let site = Fix1105DTwoClassSite()
        let sync = closed.sync(over: Fix1105DTwoClassTransport(site: site))

        let outcome = await AssistantSiriCommands.sendAfterClose(closed.siri, marked: 1, sync: sync)
        #expect(site.saves.map(\.course.courseID) == [Fix1105DTwoClassSite.ariClass.courseID])
        #expect(outcome == .partlySent(.retrying))
        #expect(!AssistantSiriCommands.closedDialog(marked: 1, parentLocker: outcome)
            .contains("hasn't gone to ParentLocker yet"))
    }
}

// MARK: - Two classes, one that can't be read

/// Two daily classes: Ari Cedar's and Maya Stone's. Maya's class list can't
/// be reached; every save is kept.
@MainActor
final class Fix1105DTwoClassSite {
    nonisolated static let ariClass = ParentLockerCourse(
        courseID: 6201, name: "Upper Elementary", period: 1, attendanceReportID: "990101"
    )
    nonisolated static let mayaClass = ParentLockerCourse(
        courseID: 6202, name: "Adolescent", period: 1, attendanceReportID: "990102"
    )

    var saves: [ParentLockerPlanner.Batch] = []

    func roster(_ course: ParentLockerCourse) throws -> ParentLockerRoster {
        guard course.courseID == Self.ariClass.courseID else { throw ParentLockerError.unreachable }
        let ari = ParentLockerRosterStudent(json: .object([
            "student_id": .int(51001),
            "first_name": .string("Ari"),
            "last_name": .string("Cedar"),
            "alternate_name": .string(""),
            "attendance": .object([
                "attendance_code": .object(["id": .string("")]),
                "attendance_code_id": .string(""),
                "comment": .string(""),
                "confirmed": .bool(false),
                "is_locked": .bool(false),
                "student_id": .int(51001),
                "course_id": .int(course.courseID)
            ])
        ]))
        return ParentLockerRoster(course: course, students: ari.map { [$0] } ?? [], marks: FixRoundSite.marks)
    }
}

/// `Fix1105DTwoClassSite`'s three requests.
nonisolated struct Fix1105DTwoClassTransport: ParentLockerTransport {
    let site: Fix1105DTwoClassSite

    func courses(on day: Date?) async throws -> [ParentLockerCourse] {
        [Fix1105DTwoClassSite.ariClass, Fix1105DTwoClassSite.mayaClass]
    }

    func roster(course: ParentLockerCourse, date: Date) async throws -> ParentLockerRoster {
        try await MainActor.run { try site.roster(course) }
    }

    func save(batch: ParentLockerPlanner.Batch) async throws -> ParentLockerSaveReply {
        await MainActor.run { site.saves.append(batch) }
        return ParentLockerSaveReply()
    }
}
