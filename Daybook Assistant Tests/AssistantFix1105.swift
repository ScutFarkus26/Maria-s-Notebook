import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// ParentLocker in the Assistant after the 2026-11-05 bug hunt (plan
// "ParentLocker in the Assistant bug hunt 2026-11-05 fixes", agent C):
// Siri answers within 8 s and the send keeps going (#7), Undo on a phone not
// signed in ends before the guide's backstop sends (#9), the bar passes the
// plain Undo window (#13), Siri says what each failure needs (#17), a move
// between Wi-Fi and cellular reaches ParentLocker (#18), and the bar's
// sign-in sheet waits for another sheet to close (#25).

@Suite("Assistant fixes 2026-11-05: ParentLocker")
@MainActor
struct AssistantFix1105 {

    /// Waits until `condition` holds, for up to `seconds`.
    private func eventually(seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - #9: Undo ends before the guide's backstop sends

    @Test("Not signed in, Close Arrival & Send's Undo goes at 50 s, before the guide's 60-s backstop (#9)")
    func unsentUndoEndsBeforeTheBackstop() {
        typealias Bar = AssistantArrivalBar
        #expect(Bar.unsentUndoLimit == 50)
        #expect(Bar.unsentUndoLimit < ParentLockerSync.backstopWait)
        let closedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(Bar.afterUndoWindow(signedIn: false, closedAt: closedAt, now: closedAt.addingTimeInterval(49))
            == .keepUndo)
        #expect(Bar.afterUndoWindow(signedIn: false, closedAt: closedAt, now: closedAt.addingTimeInterval(50))
            == .hideUndo)
        #expect(Bar.afterUndoWindow(
            signedIn: false, closedAt: closedAt, now: closedAt.addingTimeInterval(ParentLockerSync.backstopWait)
        ) == .hideUndo, "gone by the time the guide's device sends")
    }

    // MARK: - #13: the bar passes the plain Undo window

    @Test("Close Arrival & Send asks for the send after the plain Undo window; the sync adds its own second (#13)")
    func barPassesThePlainWindow() {
        #expect(AssistantArrivalBar.closeArrivalSendWindow == ParentLockerSync.closeArrivalUndoWindow)
    }

    // MARK: - #17: what Siri says for each way a send can end

    @Test("Siri names what each failure needs, in plain words (#17)")
    func siriSaysWhatEachFailureNeeds() {
        typealias Outcome = AssistantParentLockerAfterClose
        func outcome(_ state: ParentLockerStatus.State, problems: [String] = []) -> Outcome {
            AssistantSiriCommands.afterClose(ParentLockerStatus(state: state, problems: problems))
        }
        #expect(outcome(.upToDate) == .sent)
        #expect(outcome(.upToDate, problems: ["Maya S is still absent in ParentLocker."]) == .sentWithProblems)
        #expect(outcome(.pageChanged) == .pageChanged)
        #expect(outcome(.retrying) == .retrying)
        for state in [ParentLockerStatus.State.passwordRefused, .signedOut, .needsYou, .waitingForSignIn] {
            #expect(outcome(state) == .notSignedIn, "after \(state)")
        }
        #expect(outcome(.notSentYet) == .notSentYet)
        #expect(outcome(.gaveUp) == .notSentYet)
        #expect(outcome(.previewed) == .previewed)
        #expect(outcome(.notExpected) == .notExpected)

        let closed = "Arrival is closed. 1 child is marked absent."
        func said(_ outcome: Outcome) -> String { AssistantSiriCommands.closedDialog(marked: 1, parentLocker: outcome) }
        #expect(said(.pageChanged) == closed + " Attendance hasn't gone to ParentLocker yet. "
            + "ParentLocker's page has changed. Take attendance on the ParentLocker site for now.")
        // Not "in a moment": with the app in the background it may not be
        // (review of the 2026-11-05 fixes, W7).
        #expect(said(.retrying) == closed + " Attendance hasn't gone to ParentLocker yet. "
            + "It couldn't reach ParentLocker and will try again by itself. If it still hasn't gone in a few "
            + "minutes, open the Assistant to send it.")
        #expect(said(.notSignedIn) == closed + " Attendance hasn't gone to ParentLocker yet. "
            + "Open the Assistant and sign in to ParentLocker to send it.")
        #expect(said(.sentWithProblems) == closed + " Attendance went to ParentLocker, "
            + "but some children need a look. Open the Assistant to see who.")
        #expect(said(.onItsWay) == closed + " Attendance is on its way to ParentLocker.")
    }

    @Test("Nothing Siri says after the 2026-11-05 fixes carries a web address or technical words")
    func siriWordsStayPlain() {
        let outcomes: [AssistantParentLockerAfterClose] = [.sentWithProblems, .onItsWay, .retrying, .pageChanged]
        for outcome in outcomes {
            let text = AssistantSiriCommands.closedDialog(marked: 3, parentLocker: outcome).lowercased()
            for word in ["http", ".com", "cookie", "error", "keychain", "server", "request", "timeout"] {
                #expect(!text.contains(word), "\(outcome) says \(word)")
            }
        }
    }

    // MARK: - #18: a move between Wi-Fi and cellular reaches ParentLocker

    @Test("A move to another usable network is a return for ParentLocker; the same link and going offline aren't (#18)")
    func moveBetweenNetworksIsAReturn() {
        typealias Watch = AssistantNetworkWatch
        typealias Path = Watch.PathState
        let wifi = Path(usable: true, interface: .wifi)
        let cellular = Path(usable: true, interface: .cellular)
        let hotspot = Path(usable: true, interface: .wifi, expensive: true)
        let offline = Path(usable: false, interface: .other)
        #expect(Watch.cameBack(from: wifi, to: cellular))
        #expect(Watch.cameBack(from: cellular, to: wifi))
        #expect(Watch.cameBack(from: wifi, to: hotspot), "onto a phone's hotspot over Wi-Fi")
        #expect(Watch.shouldRetry(from: wifi, to: hotspot))
        #expect(Watch.cameBack(from: offline, to: wifi))
        #expect(!Watch.cameBack(from: wifi, to: wifi))
        #expect(!Watch.cameBack(from: wifi, to: offline))
        #expect(!Watch.cameBack(from: nil, to: wifi), "the first path only sets the scene")
    }

    @Test("A dead Wi-Fi straight to cellular runs ParentLocker's return once the link settles (#18)",
          .timeLimit(.minutes(1)))
    func wifiToCellularRunsTheReturn() async {
        typealias Path = AssistantNetworkWatch.PathState
        let retries = Fix1105Count()
        let returns = Fix1105Count()
        let (paths, feed) = AsyncStream.makeStream(of: Path.self)
        let watch = AssistantNetworkWatch(
            paths: paths, settle: .milliseconds(50), retry: { retries.value += 1 }, cameBack: { returns.value += 1 }
        )
        defer { watch.stop() }
        feed.yield(Path(usable: true, interface: .wifi))
        feed.yield(Path(usable: true, interface: .cellular))
        #expect(await eventually { returns.value == 1 })
        #expect(retries.value == 1)
    }

    // MARK: - #25: the bar's sign-in waits for another sheet

    @Test("The sign-in waits while another sheet is up, and opens once it closes (#25)", .timeLimit(.minutes(1)))
    func signInWaitsForAnotherSheet() async {
        let checks = Fix1105Count()
        let opens = await AssistantArrivalBar.waitWhileAnotherSheetIsUp(every: .milliseconds(10)) {
            checks.value += 1
            return checks.value < 3
        }
        #expect(opens)
        #expect(checks.value == 3, "checked until the other sheet closed")
        #expect(await AssistantArrivalBar.waitWhileAnotherSheetIsUp(every: .milliseconds(10)) { false })
    }

    @Test("A sign-in wait that's cancelled while another sheet is up doesn't open (#25)", .timeLimit(.minutes(1)))
    func cancelledSignInWaitDoesNotOpen() async {
        let wait = Task { await AssistantArrivalBar.waitWhileAnotherSheetIsUp(every: .milliseconds(10)) { true } }
        try? await Task.sleep(for: .milliseconds(50))
        wait.cancel()
        #expect(await wait.value == false)
    }

    // MARK: - #14: a signed-in phone keeps Undo while nothing has gone

    @Test("Signed in, Undo stays while the send is still to go, and goes once some of it has (#14)")
    func signedInUndoStaysWhileUnsent() {
        typealias Bar = AssistantArrivalBar
        let closedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let later = closedAt.addingTimeInterval(20)
        #expect(Bar.afterUndoWindow(signedIn: true, sendUnsent: true, closedAt: closedAt, now: later) == .keepUndo,
                "waiting to retry: Undo still stops all of it")
        #expect(Bar.afterUndoWindow(signedIn: true, sendUnsent: false, closedAt: closedAt, now: later) == .hideUndo,
                "some of the class has gone")
        #expect(Bar.afterUndoWindow(
            signedIn: true, sendUnsent: true, daySent: true, closedAt: closedAt, now: later
        ) == .hideUndo, "the day reads as sent")
        #expect(Bar.afterUndoWindow(
            signedIn: true, sendUnsent: true, closedAt: closedAt, now: closedAt.addingTimeInterval(Bar.unsentUndoLimit)
        ) == .hideUndo, "gone before the guide's backstop, signed in or not")
    }

    @Test("The Undo can't be tapped while a send is under way (#14)")
    func undoWaitsOutASend() {
        #expect(AssistantArrivalBar.undoEnabled(sending: false))
        #expect(!AssistantArrivalBar.undoEnabled(sending: true))
    }
}

// MARK: - #7: Siri answers within 8 s, and the send keeps going

// In `AssistantSiriTests`, so they run one at a time with it: closing
// arrival writes the app's own Late and Siri memories.
extension AssistantSiriTests {

    private static let fix1105Monday = "2031-01-13"

    @Test("Siri waits at most 8 s for ParentLocker (#7)")
    func siriWaitsAtMostEightSeconds() {
        #expect(AssistantSiriCommands.siriSendWait == .seconds(8))
    }

    @Test("A slow ParentLocker: Siri answers that it's on its way, and the send finishes and is recorded after (#7)",
          .timeLimit(.minutes(1)))
    func siriAnswersWhileTheSendGoesOn() async throws {
        let day = try AssistantTestSupport.day(Self.fix1105Monday)
        defer {
            SiriAttendanceChange.forget()
            AttendanceLatePhase.setLate(false, on: day)
        }
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        let attendance = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try attendance.ensureRecord(for: ari, on: day))
        #expect(attendance.updateStatus(record, to: .present))
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(.parentLocker, in: context)
        let siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 1)

        let site = FixRoundSite()
        let gate = Fix1105SaveGate()
        let recorded = Fix1105Count()
        var dependencies = ParentLockerSync.Dependencies(store: ParentLockerCoreDataStore(
            context: context, sendRecorded: { _ in recorded.value += 1 }, fixedRole: .assistant
        ))
        dependencies.secrets = FixRoundSecrets()
        dependencies.makeTransport = { _, _, _ in
            Fix1105SlowTransport(inner: FixRoundTransport(site: site), gate: gate)
        }
        dependencies.clock = FixRoundClock(siri.today)
        dependencies.policy = .live
        dependencies.unsent = ParentLockerMemoryUnsentStore()
        dependencies.refusals = ParentLockerMemoryRefusalStore()
        dependencies.importsExpected = false
        let sync = ParentLockerSync(dependencies: dependencies)
        sync.refreshSignIn()

        // ParentLocker holds the save; Siri answers once its wait is up.
        let outcome = await AssistantSiriCommands.sendAfterClose(siri, marked: 1, sync: sync, waitsAtMost: .milliseconds(200))
        #expect(outcome == .onItsWay)
        #expect(AssistantSiriCommands.closedDialog(marked: 1, parentLocker: outcome)
            == "Arrival is closed. 1 child is marked absent. Attendance is on its way to ParentLocker.")
        #expect(site.saves.isEmpty, "nothing had reached ParentLocker when Siri answered")
        #expect(await Self.fix1105Eventually { gate.waiting }, "the save is still under way, not cancelled")
        #expect(site.saves.isEmpty)

        // The save goes through: the class reaches ParentLocker and the day is recorded.
        gate.open()
        #expect(await Self.fix1105Eventually { !site.saves.isEmpty && recorded.value > 0 })
        #expect(site.saves.first?.entries.count == 2, "the whole class went")
        #expect(AttendanceEmailLog.latestSend(on: day, in: context)?.channel == .parentLocker)
        #expect(sync.status.state == .upToDate)
    }

    @Test("A quick ParentLocker: Siri still says how it went (#7)")
    func siriSaysHowAQuickSendWent() async throws {
        let day = try AssistantTestSupport.day(Self.fix1105Monday)
        defer {
            SiriAttendanceChange.forget()
            AttendanceLatePhase.setLate(false, on: day)
        }
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(.parentLocker, in: context)
        let siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 1)
        let sync = FakeParentLockerSender(endsOn: .pageChanged)
        #expect(await AssistantSiriCommands.sendAfterClose(siri, marked: 1, sync: sync) == .pageChanged)
        #expect(sync.sentDays == [siri.today])
    }

    /// Waits until `condition` holds, for up to five seconds.
    private static func fix1105Eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

// MARK: - A ParentLocker that holds its saves

/// A count a test's closures add to.
@MainActor
final class Fix1105Count {
    var value = 0
}

/// Holds every save until `open()`: ParentLocker slow to answer.
@MainActor
final class Fix1105SaveGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// A save is waiting at the gate.
    var waiting: Bool { !waiters.isEmpty }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }
}

/// `FixRoundSite`'s requests, with each save held at `gate`.
nonisolated struct Fix1105SlowTransport: ParentLockerTransport {
    let inner: FixRoundTransport
    let gate: Fix1105SaveGate

    func courses(on day: Date?) async throws -> [ParentLockerCourse] { try await inner.courses(on: day) }

    func roster(course: ParentLockerCourse, date: Date) async throws -> ParentLockerRoster {
        try await inner.roster(course: course, date: date)
    }

    func save(batch: ParentLockerPlanner.Batch) async throws -> ParentLockerSaveReply {
        await gate.wait()
        return try await inner.save(batch: batch)
    }
}
