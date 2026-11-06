import Foundation
@testable import CosmicDaybook

// One device for the fixes from the review of the 2026-11-05 engine fixes
// (report "ParentLocker in the Assistant bug hunt 2026-11-05", Review of the
// fixes, E1–E12, W2–W4), as `ParentLockerTestDevice`, over a wire that can
// also run something just after a class's save, hold the class lists while
// a test acts, fail or refuse one class's list, lose a save's reply, and
// leave a mark type off the school's page.

/// What the wire does besides the fake site's own answers.
@MainActor
final class Fix1105CWire {
    /// Runs once, just after ParentLocker takes a class's save and before
    /// its reply comes back, by `course_id`.
    var afterSave: [Int: @MainActor () -> Void] = [:]
    /// Runs once, at the next class list asked for.
    var atRoster: (@MainActor () -> Void)?
    /// While true, class lists wait until `release()`.
    var holdsRosters = false
    /// Errors the next class lists of a class throw, first first, by `course_id`.
    var rosterFailures: [Int: [ParentLockerError]] = [:]
    /// Classes whose next save ParentLocker takes, but whose reply never comes back.
    var lostReplies: Set<Int> = []
    /// Mark types the school's page doesn't list right now ("late").
    var missingMarks: Set<String> = []
    private var held: [CheckedContinuation<Void, Never>] = []

    /// Class lists waiting for `release()`.
    var waiting: Int { held.count }

    /// Lets the class lists held go, and holds no more.
    func release() {
        holdsRosters = false
        let waiting = held
        held = []
        for list in waiting { list.resume() }
    }

    fileprivate func rosterAsked(_ courseID: Int) async throws {
        if let hook = atRoster {
            atRoster = nil
            hook()
        }
        if holdsRosters { await withCheckedContinuation { held.append($0) } }
        guard var failures = rosterFailures[courseID], !failures.isEmpty else { return }
        let failure = failures.removeFirst()
        rosterFailures[courseID] = failures
        throw failure
    }

    fileprivate func saved(_ courseID: Int) {
        afterSave.removeValue(forKey: courseID)?()
    }

    fileprivate func losesReply(_ courseID: Int) -> Bool {
        lostReplies.remove(courseID) != nil
    }
}

/// The fake site's transport, through `Fix1105CWire`.
nonisolated struct Fix1105CTransport: ParentLockerTransport {
    let inner: FakeParentLockerTransport
    let wire: Fix1105CWire

    func courses(on day: Date?) async throws -> [ParentLockerCourse] {
        try await inner.courses(on: day)
    }

    func roster(course: ParentLockerCourse, date: Date) async throws -> ParentLockerRoster {
        try await wire.rosterAsked(course.courseID)
        let roster = try await inner.roster(course: course, date: date)
        let missing = await MainActor.run { wire.missingMarks }
        return ParentLockerRoster(
            course: roster.course, students: roster.students,
            marks: roster.marks.filter { !missing.contains($0.type) },
            isToday: roster.isToday, isDailyAttendance: roster.isDailyAttendance,
            attendanceReportID: roster.attendanceReportID
        )
    }

    func save(batch: ParentLockerPlanner.Batch) async throws -> ParentLockerSaveReply {
        let reply = try await inner.save(batch: batch)
        let wire = wire
        await MainActor.run { wire.saved(batch.course.courseID) }
        if await MainActor.run(body: { wire.losesReply(batch.course.courseID) }) {
            throw ParentLockerError.unreachable
        }
        return reply
    }
}

/// One device, as `ParentLockerTestDevice`, on `Fix1105CWire`.
@MainActor
struct Fix1105CDevice {

    typealias Device = ParentLockerTestDevice

    let store: FakeParentLockerStore
    let secrets: FakeParentLockerSecrets
    let unsent: ParentLockerMemoryUnsentStore
    let background = FakeParentLockerBackground()
    let wire = Fix1105CWire()
    let sync: ParentLockerSync

    init(
        site: FakeParentLocker,
        clock: FakeParentLockerClock,
        role: CDClassroomMembership.ClassroomRole = .leadGuide,
        secrets: FakeParentLockerSecrets = FakeParentLockerSecrets(),
        unsent: ParentLockerMemoryUnsentStore = ParentLockerMemoryUnsentStore(),
        arrivalClosed: Bool = true,
        sent: Bool = false,
        marks: [UUID: ParentLockerPlanner.DayMark] = Fix1105AMarks.closed
    ) {
        store = FakeParentLockerStore(state: ParentLockerDay(
            method: .parentLocker, site: FakeParentLocker.host, role: role, isSchoolDay: true,
            arrivalClosed: arrivalClosed, sentToParentLocker: sent, children: Device.children, marks: marks
        ))
        self.secrets = secrets
        self.unsent = unsent
        let wire = wire
        var dependencies = ParentLockerSync.Dependencies(store: store)
        dependencies.secrets = secrets
        dependencies.makeTransport = { _, cookies, _ in
            Fix1105CTransport(inner: FakeParentLockerTransport(site: site, cookies: cookies), wire: wire)
        }
        dependencies.signIn = { credential, _ in try site.signIn(credential) }
        dependencies.clock = clock
        dependencies.policy = .live
        dependencies.unsent = unsent
        dependencies.background = background
        dependencies.isInForeground = { true }
        dependencies.importsExpected = false
        dependencies.returnNeedsAbsence = false
        sync = ParentLockerSync(dependencies: dependencies)
        sync.start(watching: nil)
    }

    /// This device marks children on `day`: the store holds the marks, and the sync hears the save.
    func marks(_ changes: [UUID: ParentLockerPlanner.DayMark], on day: Date = Device.morning) {
        store.state.marks.merge(changes) { $1 }
        sync.noteChanges(Set(changes.keys), imported: false, on: day)
    }

    /// Marks made on another device arrive here by sync.
    func imports(_ changes: [UUID: ParentLockerPlanner.DayMark], on day: Date = Device.morning) {
        store.state.marks.merge(changes) { $1 }
        sync.noteChanges(Set(changes.keys), imported: true, on: day)
    }

    /// Close Arrival's Undo as a screen makes it: the sync's, then the
    /// notebook's marks back as they were (Bea unmarked, arrival open).
    func undoesCloseArrival() {
        sync.cancelCloseArrivalSend()
        store.state.arrivalClosed = false
        store.state.marks[Device.bea] = nil
    }
}

/// Lets other work on the main actor run until `condition` holds, or gives up.
@MainActor
func fix1105CYield(until condition: @MainActor () -> Bool) async {
    for _ in 0..<2_000 where !condition() { await Task.yield() }
}
