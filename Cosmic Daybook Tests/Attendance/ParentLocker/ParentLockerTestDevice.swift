import Foundation
@testable import CosmicDaybook

// One device for the ParentLocker sync's tests: its notebook, keychain and
// sync, on the fake site and clock (`ParentLockerSyncFakes`).

/// One device: its notebook, keychain and sync, on the shared site and clock.
@MainActor
struct ParentLockerTestDevice {

    /// The class as the notebook has it, matching `FakeParentLocker.kids` by name.
    static let wren = UUID()
    static let june = UUID()
    static let marisol = UUID()
    static let odile = UUID()
    static let bea = UUID()

    static let children = [
        ParentLockerPlanner.Child(id: wren, firstName: "Wren", lastName: "Halloway"),
        ParentLockerPlanner.Child(id: june, firstName: "Jun", lastName: "Ashby", nickname: "June"),
        ParentLockerPlanner.Child(id: marisol, firstName: "Marisol", lastName: "Pena"),
        ParentLockerPlanner.Child(id: odile, firstName: "Odile", lastName: "Brandt"),
        ParentLockerPlanner.Child(id: bea, firstName: "Bea", lastName: "Marchetti")
    ]

    /// Monday 2026-10-12, 8:00 in the app's calendar.
    static var morning: Date {
        AppCalendar.shared.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8)) ?? Date()
    }

    static func mark(
        _ status: AttendanceStatus, reason: String = AbsenceReason.none.rawValue
    ) -> ParentLockerPlanner.DayMark {
        ParentLockerPlanner.DayMark(statusRaw: status.rawValue, absenceReasonRaw: reason)
    }

    let store: FakeParentLockerStore
    let secrets: FakeParentLockerSecrets
    let unsent: ParentLockerMemoryUnsentStore
    let background = FakeParentLockerBackground()
    let sync: ParentLockerSync

    init(
        site: FakeParentLocker,
        clock: FakeParentLockerClock,
        role: CDClassroomMembership.ClassroomRole = .leadGuide,
        policy: ParentLockerSavePolicy = .live,
        secrets: FakeParentLockerSecrets = FakeParentLockerSecrets(),
        unsent: ParentLockerMemoryUnsentStore = ParentLockerMemoryUnsentStore(),
        importsExpected: Bool = false,
        returnNeedsAbsence: Bool = false,
        inForeground: @escaping @MainActor () -> Bool = { true },
        arrivalClosed: Bool = true,
        sent: Bool = false,
        marks: [UUID: ParentLockerPlanner.DayMark] = [:]
    ) {
        store = FakeParentLockerStore(state: ParentLockerDay(
            method: .parentLocker, site: FakeParentLocker.host, role: role, isSchoolDay: true,
            arrivalClosed: arrivalClosed, sentToParentLocker: sent, children: Self.children, marks: marks
        ))
        self.secrets = secrets
        self.unsent = unsent
        var dependencies = ParentLockerSync.Dependencies(store: store)
        dependencies.secrets = secrets
        dependencies.makeTransport = { _, cookies, _ in FakeParentLockerTransport(site: site, cookies: cookies) }
        dependencies.signIn = { credential, _ in
            for _ in 0..<site.signInYields { await Task.yield() }
            return try site.signIn(credential)
        }
        dependencies.clock = clock
        dependencies.policy = policy
        dependencies.unsent = unsent
        dependencies.background = background
        dependencies.isInForeground = inForeground
        dependencies.importsExpected = importsExpected
        dependencies.returnNeedsAbsence = returnNeedsAbsence
        sync = ParentLockerSync(dependencies: dependencies)
        sync.start(watching: nil)
    }

    /// This device marks children (a tap, Siri, MCP) on `day`: the store
    /// holds the marks, and the sync hears the save.
    func marks(_ changes: [UUID: ParentLockerPlanner.DayMark], on day: Date = Self.morning) {
        store.state.marks.merge(changes) { $1 }
        sync.noteChanges(Set(changes.keys), imported: false, on: day)
    }

    /// Marks made on another device arrive here by sync.
    func imports(_ changes: [UUID: ParentLockerPlanner.DayMark], on day: Date = Self.morning) {
        store.state.marks.merge(changes) { $1 }
        sync.noteChanges(Set(changes.keys), imported: true, on: day)
    }
}
