import Foundation
import CoreData
import Synchronization
import UserNotifications
@testable import Daybook_Assistant

// What `AssistantFix1103FD` runs on: a ParentLocker phone in memory and a
// notification center that counts its reads.

// MARK: - A ParentLocker device in memory

/// One signed-in phone over a one-class site whose save waits until the
/// test lets it go, on a clock that moves only by hand.
@MainActor
struct FD1103Device {
    static let wren = UUID()

    let site: FD1103Site
    let store: FD1103Store
    let secrets: FD1103Secrets
    let unsent = ParentLockerMemoryUnsentStore()
    let clock: FixRoundClock
    let sync: ParentLockerSync

    init(secrets: FD1103Secrets = FD1103Secrets(signedIn: true), arrivalClosed: Bool = true) {
        let site = FD1103Site()
        self.site = site
        // Monday 2026-10-12, 8:00.
        clock = FixRoundClock(
            AppCalendar.shared.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8)) ?? Date()
        )
        store = FD1103Store(state: ParentLockerDay(
            method: .parentLocker, site: "school.parentlocker.test", role: .assistant, isSchoolDay: true,
            arrivalClosed: arrivalClosed,
            children: [ParentLockerPlanner.Child(id: Self.wren, firstName: "Wren", lastName: "Halloway")],
            marks: [Self.wren: ParentLockerPlanner.DayMark(
                statusRaw: AttendanceStatus.present.rawValue, absenceReasonRaw: AbsenceReason.none.rawValue
            )]
        ))
        self.secrets = secrets
        var dependencies = ParentLockerSync.Dependencies(store: store)
        dependencies.secrets = secrets
        dependencies.makeTransport = { _, _, _ in FD1103Transport(site: site) }
        dependencies.clock = clock
        dependencies.policy = .live
        dependencies.unsent = unsent
        dependencies.refusals = ParentLockerMemoryRefusalStore()
        dependencies.importsExpected = false
        dependencies.isInForeground = { true }
        sync = ParentLockerSync(dependencies: dependencies)
        sync.start(watching: nil)
    }
}

/// One daily class holding Wren Halloway, whose save can be held.
@MainActor
final class FD1103Site {
    nonisolated static let course = ParentLockerCourse(
        courseID: 7101, name: "Upper Elementary", period: 1, attendanceReportID: "990101"
    )
    private(set) var isHoldingSave = false
    private(set) var saves = 0
    private var held: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func roster() -> ParentLockerRoster {
        let student = ParentLockerRosterStudent(json: .object([
            "student_id": .int(60001),
            "first_name": .string("Wren"),
            "last_name": .string("Halloway"),
            "alternate_name": .string(""),
            "attendance": .object([
                "attendance_code": .object(["id": .string("")]),
                "attendance_code_id": .string(""),
                "comment": .string(""),
                "confirmed": .bool(false),
                "is_locked": .bool(false),
                "student_id": .int(60001),
                "course_id": .int(Self.course.courseID)
            ])
        ]))
        return ParentLockerRoster(course: Self.course, students: student.map { [$0] } ?? [], marks: [
            ParentLockerMark(id: "701", name: "Present", type: "present"),
            ParentLockerMark(id: "703", name: "Absent", type: "absent")
        ])
    }

    /// A save: waits until `releaseSave`.
    func save() async {
        saves += 1
        guard !isReleased else { return }
        isHoldingSave = true
        await withCheckedContinuation { held = $0 }
        isHoldingSave = false
    }

    func releaseSave() {
        isReleased = true
        held?.resume()
        held = nil
    }
}

nonisolated struct FD1103Transport: ParentLockerTransport {
    let site: FD1103Site

    func courses(on day: Date?) async throws -> [ParentLockerCourse] { [FD1103Site.course] }

    func roster(course: ParentLockerCourse, date: Date) async throws -> ParentLockerRoster {
        await site.roster()
    }

    func save(batch: ParentLockerPlanner.Batch) async throws -> ParentLockerSaveReply {
        await site.save()
        return ParentLockerSaveReply()
    }
}

/// A sign-in that is there or not, counting the cookie deletes.
nonisolated final class FD1103Secrets: ParentLockerSecrets {
    private let deletes = Mutex(0)
    private let signedIn: Bool

    init(signedIn: Bool) { self.signedIn = signedIn }

    var cookieDeletes: Int { deletes.withLock { $0 } }

    func credential(site: String) throws -> ParentLockerKeychain.Credential? {
        signedIn ? ParentLockerKeychain.Credential(email: "wren@school.test", password: "made-up") : nil
    }
    func hasPassword(site: String) throws -> Bool { signedIn }
    func passwordModified(site: String) throws -> Date? { signedIn ? Date(timeIntervalSinceReferenceDate: 0) : nil }
    func savePassword(_ credential: ParentLockerKeychain.Credential, site: String) throws {}
    func deletePassword(site: String) throws {}
    func cookies(site: String) throws -> [ParentLockerCookie] {
        signedIn ? [ParentLockerCookie(name: "PHPSESSID", value: "good", domain: site)] : []
    }
    func saveCookies(_ cookies: [ParentLockerCookie], site: String) throws {}
    func deleteCookies(site: String) throws { deletes.withLock { $0 += 1 } }
}

/// One phone's notebook: the day as `state` holds it, counting its reads.
@MainActor
final class FD1103Store: ParentLockerStore {
    var state: ParentLockerDay
    var recordedSends: [Date] = []
    /// Reads of the day and of children's marks.
    var reads = 0

    init(state: ParentLockerDay) { self.state = state }

    var site: String { state.site }

    func day(_ day: Date, withChildren: Bool) -> ParentLockerDay {
        reads += 1
        var result = state
        result.sentToParentLocker = state.sentToParentLocker || !recordedSends.isEmpty
        if !withChildren {
            result.children = []
            result.marks = [:]
        }
        return result
    }

    func children(inRecords records: [NSManagedObjectID], on day: Date) -> Set<UUID> { [] }

    func marks(of children: Set<UUID>, on day: Date) -> [UUID: ParentLockerPlanner.DayMark] {
        reads += 1
        return state.marks.filter { children.contains($0.key) }
    }

    func recordSend(on day: Date) -> Bool {
        recordedSends.append(day)
        return true
    }

    func noteNotExpected(on day: Date) {}

    func writeMatches(_ matches: [UUID: String?]) -> Bool { true }
}

/// The tests' notification center, counting the permission reads too.
@MainActor
final class FD1103CountingCenter: ReminderCenter {
    let inner = FakeReminderCenter()
    private(set) var statusReads = 0

    func authorizationStatus() async -> UNAuthorizationStatus {
        statusReads += 1
        return await inner.authorizationStatus()
    }
    func requestAuthorization() async -> Bool { await inner.requestAuthorization() }
    func pendingRequests() async -> [UNNotificationRequest] { await inner.pendingRequests() }
    func removePendingRequests(withIdentifiers identifiers: [String]) {
        inner.removePendingRequests(withIdentifiers: identifiers)
    }
    func add(_ request: UNNotificationRequest) async throws { try await inner.add(request) }
}
