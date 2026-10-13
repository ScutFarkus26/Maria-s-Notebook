import Foundation
import CoreData
import Synchronization
import Testing
@testable import Daybook_Assistant

// The review of the afternoon fixes (plan "ParentLocker bug hunt afternoon
// fixes", Phase 2), the Assistant's side: Siri's Close Arrival goes as a
// Close Arrival & Send (so Siri's Undo stops a failed send's retry), a day
// ParentLocker isn't expecting, a child left out of ParentLocker, and the
// line beside Send. The real sync where it matters, over a site in memory.

@Suite("Assistant ParentLocker fix round")
@MainActor
struct AssistantParentLockerFixRoundTests {

    @Test("A child left out of ParentLocker doesn't keep the Assistant from offering Send")
    func notMatchedChildDoesNotBlockSend() throws {
        let monday = try AssistantTestSupport.day("2026-10-12")
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        maya.parentLockerID = "none"
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.ensureRecord(for: ari, on: monday))
        #expect(store.updateStatus(record, to: .present))
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(.parentLocker, in: context)
        let viewModel = AssistantTestSupport.viewModel(stack, on: monday)
        #expect(viewModel.unmarkedCount == 1, "Maya isn't marked")
        #expect(viewModel.frontDesk.offersParentLockerSend(by: viewModel), "but she never goes to ParentLocker")
    }

    @Test("Beside its own Send button, the line doesn't also say to send it")
    func readyLineHidesBesideSend() {
        typealias Row = AssistantParentLockerRow
        let ready = ParentLockerStatus(state: .readyToSend, problems: ["Ari is locked"])
        #expect(Row.shownStatus(offersSend: true, status: ready).message == nil)
        #expect(Row.shownStatus(offersSend: true, status: ready).problems == ["Ari is locked"])
        #expect(!Row.showsStatusMenu(
            offersSend: true, status: ParentLockerStatus(state: .readyToSend), sentSummary: nil
        ))
        #expect(Row.shownStatus(offersSend: false, status: ready) == ready)
    }
}

// In `AssistantSiriTests`, so they run one at a time with it: closing
// arrival writes the app's own Late and Siri memories.
extension AssistantSiriTests {

    private static let fixRoundMonday = "2031-01-06"

    /// Ari in already, and Maya not: Siri closes arrival, marking Maya absent.
    private static func siriClosesWithAriIn() async throws -> (SiriAttendance, Date) {
        let day = try AssistantTestSupport.day(Self.fixRoundMonday)
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.ensureRecord(for: ari, on: day))
        #expect(store.updateStatus(record, to: .present))
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(.parentLocker, in: context)
        let siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 1)
        return (siri, day)
    }

    @Test("H2: Siri's Undo stops the retry of a Close Arrival whose send failed, and arrival is open again")
    func siriUndoStopsTheRetry() async throws {
        let (siri, day) = try await Self.siriClosesWithAriIn()
        defer {
            SiriAttendanceChange.forget()
            AttendanceLatePhase.setLate(false, on: day)
        }
        let site = FixRoundSite()
        site.failuresLeft = 1
        let (sync, clock) = site.sync(on: siri.context, at: siri.today)
        #expect(await AssistantSiriCommands.sendAfterClose(siri, sync: sync) == .notSentYet)
        #expect(site.saves.isEmpty)

        // "Undo that", as `SiriHost.closeArrivalUndone` does it with the class's sync.
        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
        AssistantSiriCommands.undoCloseSend(on: siri.today, sync: sync)
        clock.advance(by: ParentLockerSync.retryWaits[0])
        await sync.runDue()
        #expect(site.saves.isEmpty, "the reopened class doesn't go: Ari's Present waits for arrival to close")
        #expect(!sync.isAfter(sync.store.day(siri.today, withChildren: false), on: siri.today))
    }

    @Test("Siri's Close Arrival says plainly when ParentLocker isn't expecting attendance today")
    func siriCloseArrivalNotExpected() async throws {
        let (siri, day) = try await Self.siriClosesWithAriIn()
        defer {
            SiriAttendanceChange.forget()
            AttendanceLatePhase.setLate(false, on: day)
        }
        let site = FixRoundSite()
        site.notExpectedToday = true
        let (sync, _) = site.sync(on: siri.context, at: siri.today)
        let outcome = await AssistantSiriCommands.sendAfterClose(siri, sync: sync)
        #expect(AssistantSiriCommands.closedDialog(marked: 1, parentLocker: outcome)
            == "Arrival is closed. 1 child is marked absent. ParentLocker isn't expecting attendance today.")
        #expect(site.saves.isEmpty)
    }
}

// MARK: - A ParentLocker site in memory

/// One daily class holding Ari Cedar and Maya Stone, the marks each holds,
/// and every save made of it.
@MainActor
final class FixRoundSite {
    nonisolated static let course = ParentLockerCourse(
        courseID: 6101, name: "Upper Elementary", period: 1, attendanceReportID: "990001"
    )
    nonisolated static let marks = [
        ParentLockerMark(id: "701", name: "Present", type: "present"),
        ParentLockerMark(id: "702", name: "Late", type: "late"),
        ParentLockerMark(id: "703", name: "Absent", type: "absent")
    ]

    struct Kid {
        let first: String
        let last: String
        var markID: String?
    }

    /// By ParentLocker's student id.
    var kids: [Int: Kid] = [
        50001: Kid(first: "Ari", last: "Cedar"),
        50002: Kid(first: "Maya", last: "Stone")
    ]
    var saves: [ParentLockerPlanner.Batch] = []
    /// How many more requests fail as unreachable.
    var failuresLeft = 0
    /// Today's page lists the class as not expecting attendance.
    var notExpectedToday = false

    fileprivate func check() throws {
        guard failuresLeft > 0 else { return }
        failuresLeft -= 1
        throw ParentLockerError.unreachable
    }

    fileprivate func roster() -> ParentLockerRoster {
        let students = kids.sorted { $0.key < $1.key }.compactMap { id, kid in
            ParentLockerRosterStudent(json: .object([
                "student_id": .int(id),
                "first_name": .string(kid.first),
                "last_name": .string(kid.last),
                "alternate_name": .string(""),
                "attendance": .object([
                    "attendance_code": .object(["id": .string(kid.markID ?? "")]),
                    "attendance_code_id": .string(kid.markID ?? ""),
                    "comment": .string(""),
                    "confirmed": .bool(kid.markID != nil),
                    "is_locked": .bool(false),
                    "student_id": .int(id),
                    "course_id": .int(Self.course.courseID)
                ])
            ]))
        }
        return ParentLockerRoster(course: Self.course, students: students, marks: Self.marks)
    }

    fileprivate func apply(_ batch: ParentLockerPlanner.Batch) {
        saves.append(batch)
        for entry in batch.entries {
            guard let id = Int(entry.studentID) else { continue }
            kids[id]?.markID = entry.attendance["attendance_code"]?["id"]?.stringValue
        }
    }

    /// The class's sync on `context`, as the Assistant makes it, over this
    /// site, signed in, on a clock set to `now` that moves only by hand.
    func sync(on context: NSManagedObjectContext, at now: Date) -> (ParentLockerSync, FixRoundClock) {
        let clock = FixRoundClock(now)
        var dependencies = ParentLockerSync.Dependencies(store: ParentLockerCoreDataStore(
            context: context, sendRecorded: { _ in }, fixedRole: .assistant
        ))
        dependencies.secrets = FixRoundSecrets()
        dependencies.makeTransport = { _, _, _ in FixRoundTransport(site: self) }
        dependencies.clock = clock
        dependencies.policy = .live
        dependencies.unsent = ParentLockerMemoryUnsentStore()
        dependencies.refusals = ParentLockerMemoryRefusalStore()
        dependencies.importsExpected = false
        let sync = ParentLockerSync(dependencies: dependencies)
        sync.refreshSignIn()
        return (sync, clock)
    }
}

/// The site's three requests, against `FixRoundSite`.
nonisolated struct FixRoundTransport: ParentLockerTransport {
    let site: FixRoundSite

    func courses(on day: Date?) async throws -> [ParentLockerCourse] {
        try await MainActor.run {
            try site.check()
            let course = FixRoundSite.course
            guard day == nil, site.notExpectedToday else { return [course] }
            return [ParentLockerCourse(
                courseID: course.courseID, name: course.name, period: course.period,
                attendanceReportID: course.attendanceReportID, reportStatus: "not_expected"
            )]
        }
    }

    func roster(course: ParentLockerCourse, date: Date) async throws -> ParentLockerRoster {
        try await MainActor.run {
            try site.check()
            return site.roster()
        }
    }

    func save(batch: ParentLockerPlanner.Batch) async throws -> ParentLockerSaveReply {
        try await MainActor.run {
            try site.check()
            site.apply(batch)
            return ParentLockerSaveReply()
        }
    }
}

/// Time moves only when a test says; the sync's own wake never fires.
nonisolated final class FixRoundClock: ParentLockerClock {
    private let current: Mutex<Date>

    init(_ start: Date) { current = Mutex(start) }

    var now: Date { current.withLock { $0 } }

    func advance(by seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }

    func sleep(until deadline: Date) async throws {
        try await Task.sleep(for: .seconds(1_000_000))
    }
}

/// A sign-in that's always there: a made-up password and a working cookie.
nonisolated struct FixRoundSecrets: ParentLockerSecrets {
    private static let credential = ParentLockerKeychain.Credential(email: "ari@school.test", password: "made-up")

    func credential(site: String) throws -> ParentLockerKeychain.Credential? { Self.credential }
    func hasPassword(site: String) throws -> Bool { true }
    func passwordModified(site: String) throws -> Date? { Date(timeIntervalSinceReferenceDate: 0) }
    func savePassword(_ credential: ParentLockerKeychain.Credential, site: String) throws {}
    func deletePassword(site: String) throws {}
    func cookies(site: String) throws -> [ParentLockerCookie] {
        [ParentLockerCookie(name: "PHPSESSID", value: "good", domain: site)]
    }
    func saveCookies(_ cookies: [ParentLockerCookie], site: String) throws {}
    func deleteCookies(site: String) throws {}
}
