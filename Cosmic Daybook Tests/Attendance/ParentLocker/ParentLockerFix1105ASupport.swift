import Foundation
@testable import CosmicDaybook

// One device for the engine fixes of the 2026-11-05 bug hunt (report
// "ParentLocker in the Assistant bug hunt 2026-11-05"), as
// `ParentLockerTestDevice`, over a wire that can also fail one class's
// roster, lose a save's reply after ParentLocker took it, run something in
// the middle of a run, and hand back the transports' cookie callbacks.

/// What the wire does besides the fake site's own answers.
@MainActor
final class Fix1105AWire {
    /// Errors the next roster requests of a class throw, first first, by `course_id`.
    var rosterFailures: [Int: [ParentLockerError]] = [:]
    /// Classes whose next save ParentLocker takes, but whose reply never comes back.
    var lostReplies: Set<Int> = []
    /// Runs once, at the next roster request: something done while a run is under way.
    var duringRun: (@MainActor () -> Void)?
    /// Each transport's "the site set cookies" callback, as the sync handed it.
    var cookieCallbacks: [@Sendable ([ParentLockerCookie]) -> Void] = []

    fileprivate func rosterRequested(_ courseID: Int) throws {
        if let hook = duringRun {
            duringRun = nil
            hook()
        }
        guard var failures = rosterFailures[courseID], !failures.isEmpty else { return }
        let failure = failures.removeFirst()
        rosterFailures[courseID] = failures
        throw failure
    }

    fileprivate func losesReply(_ courseID: Int) -> Bool {
        lostReplies.remove(courseID) != nil
    }
}

/// The fake site's transport, through `Fix1105AWire`.
nonisolated struct Fix1105ATransport: ParentLockerTransport {
    let inner: FakeParentLockerTransport
    let wire: Fix1105AWire

    func courses(on day: Date?) async throws -> [ParentLockerCourse] {
        try await inner.courses(on: day)
    }

    func roster(course: ParentLockerCourse, date: Date) async throws -> ParentLockerRoster {
        let wire = wire
        try await MainActor.run { try wire.rosterRequested(course.courseID) }
        return try await inner.roster(course: course, date: date)
    }

    func save(batch: ParentLockerPlanner.Batch) async throws -> ParentLockerSaveReply {
        let reply = try await inner.save(batch: batch)
        let wire = wire
        if await MainActor.run(body: { wire.losesReply(batch.course.courseID) }) {
            throw ParentLockerError.unreachable
        }
        return reply
    }
}

/// One device, as `ParentLockerTestDevice`, on `Fix1105AWire`.
@MainActor
struct Fix1105ADevice {

    typealias Device = ParentLockerTestDevice

    let store: FakeParentLockerStore
    let secrets: FakeParentLockerSecrets
    let unsent: ParentLockerMemoryUnsentStore
    let background = FakeParentLockerBackground()
    let wire = Fix1105AWire()
    let sync: ParentLockerSync

    init(
        site: FakeParentLocker,
        clock: FakeParentLockerClock,
        role: CDClassroomMembership.ClassroomRole = .leadGuide,
        secrets: FakeParentLockerSecrets = FakeParentLockerSecrets(),
        unsent: ParentLockerMemoryUnsentStore = ParentLockerMemoryUnsentStore(),
        arrivalClosed: Bool = true,
        sent: Bool = false,
        marks: [UUID: ParentLockerPlanner.DayMark] = [:],
        signIn: ParentLockerSync.SignIn? = nil
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
        dependencies.makeTransport = { _, cookies, changed in
            wire.cookieCallbacks.append(changed)
            return Fix1105ATransport(inner: FakeParentLockerTransport(site: site, cookies: cookies), wire: wire)
        }
        dependencies.signIn = signIn ?? { credential, _ in try site.signIn(credential) }
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
}

/// Something a hook sets for the test to read after.
@MainActor
final class Fix1105ABox<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// The class as Close Arrival finds it: everyone in but Bea, whom it marks
/// absent; Marisol came late.
enum Fix1105AMarks {
    typealias Device = ParentLockerTestDevice

    static let automatic = Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw)

    static let closed: [UUID: ParentLockerPlanner.DayMark] = [
        Device.wren: Device.mark(.present), Device.june: Device.mark(.present),
        Device.marisol: Device.mark(.tardy), Device.odile: Device.mark(.present),
        Device.bea: automatic
    ]

    static let everyonePresent: [UUID: ParentLockerPlanner.DayMark] = Device.children.reduce(into: [:]) {
        $0[$1.id] = Device.mark(.present)
    }

    /// Close Arrival & Send's send goes a second after its Undo's 6 s (#13).
    static let sendsAfter: TimeInterval = 7
}
