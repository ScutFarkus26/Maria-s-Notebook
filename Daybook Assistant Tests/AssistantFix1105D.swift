import Foundation
import CoreData
import Testing
import UIKit
@testable import Daybook_Assistant

// The review of the 2026-11-05 fixes (plan "ParentLocker in the Assistant bug
// hunt 2026-11-05 fixes", Phase 2), the Assistant's side: Siri's Undo waits
// out a Close Arrival send under way (W1), the bar's Undo can't be tapped
// while one is (W6), Siri says plainly what each way a send ends needs and
// never that nothing went after part of it did (W7, W8), an `isExpensive`
// flap on the same Wi-Fi isn't a move (W10), and the sign-in looks at every
// foreground window for another sheet (W11). Tests set the engine's
// `closeArrivalSendUnderWay` by hand, as the engine sets it during a run.

@Suite("Assistant fixes 2026-11-05 D: the review")
@MainActor
struct AssistantFix1105D {

    typealias Bar = AssistantArrivalBar
    typealias Outcome = AssistantParentLockerAfterClose

    /// Waits until `condition` holds, for up to `seconds`.
    private func eventually(seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// The class's sync over `FixRoundSite`, on a fresh in-memory stack.
    private func classSync() throws -> ParentLockerSync {
        let stack = try AssistantTestSupport.makeStack()
        let day = try AssistantTestSupport.day("2031-01-20")
        return FixRoundSite().sync(on: stack.viewContext, at: day.addingTimeInterval(9 * 3_600)).0
    }

    // MARK: - W6: the bar's Undo while the send is under way

    @Test("W6: the bar's Undo can't be tapped while Close Arrival's send is under way, and comes back if it fails")
    func barUndoWaitsWhileUnderWay() throws {
        let sync = try classSync()
        #expect(Bar.undoEnabled(for: sync))
        // Taken to run, still waiting for a class list: nothing is sending yet.
        sync.closeArrivalSendUnderWay = true
        #expect(sync.status.state != .sending)
        #expect(!Bar.undoEnabled(for: sync), "a class may reach ParentLocker whatever Undo does now")
        sync.status = ParentLockerStatus(state: .sending)
        #expect(!Bar.undoEnabled(for: sync))
        // The send failed and waits to retry: Undo stops all of it again.
        sync.closeArrivalSendUnderWay = false
        sync.status = ParentLockerStatus(state: .retrying)
        #expect(Bar.undoEnabled(for: sync))
        #expect(Bar.undoEnabled(for: nil), "no sync, nothing to wait for")
        #expect(!Bar.undoEnabled(sending: false, underWay: true))
        #expect(Bar.undoEnabled(sending: false, underWay: false))
    }

    @Test("W6: R9 stays: the Undo still goes at 50 s, whatever the send is doing")
    func undoLimitStays() {
        let closedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(Bar.unsentUndoLimit == 50)
        #expect(Bar.afterUndoWindow(
            signedIn: true, sendUnsent: true, closedAt: closedAt, now: closedAt.addingTimeInterval(50)
        ) == .hideUndo)
    }

    // MARK: - W7, W8: what Siri says after Close Arrival

    @Test("W8: each way a send ends has its own answer")
    func eachStateHasItsOwnAnswer() {
        func outcome(_ state: ParentLockerStatus.State, problems: [String] = []) -> Outcome {
            AssistantSiriCommands.afterClose(ParentLockerStatus(state: state, problems: problems))
        }
        #expect(outcome(.refused) == .refused)
        #expect(outcome(.keychainTrouble) == .keychainTrouble)
        #expect(outcome(.idle, problems: ["None of the class's children were found in ParentLocker."]) == .noneFound)
        #expect(outcome(.idle) == .notSent)
        #expect(outcome(.waitingForArrival) == .notSent)
        #expect(outcome(.off) == .notPicked, "attendance goes by email after all: nothing to say about ParentLocker")
        // As decided for #17.
        #expect(outcome(.retrying) == .retrying)
        #expect(outcome(.pageChanged) == .pageChanged)
        #expect(outcome(.gaveUp) == .notSentYet)
        #expect(outcome(.notSentYet) == .notSentYet)
        #expect(outcome(.passwordRefused) == .notSignedIn)
    }

    @Test("W8: only what opening the Assistant fixes says to open it")
    func openTheAssistantOnlyWhereItHelps() {
        func said(_ outcome: Outcome) -> String { AssistantSiriCommands.closedDialog(marked: 2, parentLocker: outcome) }
        for outcome in [Outcome.refused, .pageChanged, .notExpected, .sent, .onItsWay, .previewed, .notPicked] {
            #expect(!said(outcome).contains("Open the Assistant"), "\(outcome)")
            #expect(!said(outcome).contains("open the Assistant"), "\(outcome)")
        }
        let closed = "Arrival is closed. 2 children are marked absent."
        #expect(said(.refused) == closed + " Attendance hasn't gone to ParentLocker yet. "
            + "ParentLocker didn't take it. Check today's attendance on the ParentLocker site.")
        #expect(said(.keychainTrouble) == closed + " Attendance hasn't gone to ParentLocker yet. "
            + "This iPhone couldn't use its saved ParentLocker sign-in. Restart the iPhone, then open the Assistant "
            + "to send it.")
        #expect(said(.noneFound) == closed + " None of the class's children were found in ParentLocker, so nothing "
            + "went. Open the Assistant and check that it's signed in with your school's ParentLocker account.")
        #expect(said(.notSent) == closed + " Attendance didn't go to ParentLocker. Open the Assistant to see why.")
    }

    @Test("W7: a retry isn't promised for a moment: Siri says it will try again, and what to do if it hasn't gone")
    func retryIsNotPromisedForAMoment() {
        let said = AssistantSiriCommands.closedDialog(marked: 1, parentLocker: .retrying)
        #expect(!said.contains("in a moment"))
        #expect(said == "Arrival is closed. 1 child is marked absent. Attendance hasn't gone to ParentLocker yet. "
            + "It couldn't reach ParentLocker and will try again by itself. If it still hasn't gone in a few "
            + "minutes, open the Assistant to send it.")
    }

    @Test("W7: after part of the class went, Siri never says nothing has gone")
    func partSentIsNotNothing() {
        let partly = AssistantSiriCommands.afterClose(ParentLockerStatus(state: .retrying), unsent: false)
        #expect(partly == .partlySent(.retrying))
        #expect(AssistantSiriCommands.afterClose(ParentLockerStatus(state: .retrying), unsent: true) == .retrying)
        #expect(AssistantSiriCommands.afterClose(ParentLockerStatus(state: .upToDate), unsent: false) == .sent)
        #expect(AssistantSiriCommands.afterClose(ParentLockerStatus(state: .pageChanged), unsent: false)
            == .partlySent(.pageChanged))

        let said = AssistantSiriCommands.closedDialog(marked: 1, parentLocker: partly)
        #expect(!said.contains("hasn't gone to ParentLocker yet"))
        #expect(said == "Arrival is closed. 1 child is marked absent. Some of today's attendance may already be in "
            + "ParentLocker, but not all of it went. It couldn't reach ParentLocker for the rest and will try "
            + "again by itself. If the rest still hasn't gone in a few minutes, open the Assistant to send it.")
        #expect(AssistantSiriCommands.closedDialog(marked: 1, parentLocker: .partlySent(.pageChanged))
            == "Arrival is closed. 1 child is marked absent. Some of today's attendance may already be in "
            + "ParentLocker, but not all of it went. ParentLocker's page has changed. Take attendance on the "
            + "ParentLocker site for now.")
    }

    @Test("W7, W8: nothing Siri says about ParentLocker carries a web address or technical words")
    func everyAnswerIsPlain() {
        let outcomes: [Outcome] = [
            .notPicked, .sent, .sentWithProblems, .previewed, .notSignedIn, .onItsWay, .retrying, .pageChanged,
            .refused, .noneFound, .keychainTrouble, .notSentYet, .notSent, .notExpected,
            .partlySent(.retrying), .partlySent(.notSignedIn), .partlySent(.refused), .partlySent(.notSentYet)
        ]
        for outcome in outcomes {
            let text = AssistantSiriCommands.closedDialog(marked: 3, parentLocker: outcome).lowercased()
            for word in ["http", ".com", "cookie", "error", "keychain", "server", "request", "timeout", "status"] {
                #expect(!text.contains(word), "\(outcome) says \(word)")
            }
        }
    }

    // MARK: - W10: an `isExpensive` flap on the same Wi-Fi

    @Test("W10: isExpensive flapping on the same Wi-Fi and settling where it was isn't a move", .timeLimit(.minutes(1)))
    func expensiveFlapIsNotAMove() async throws {
        typealias Path = AssistantNetworkWatch.PathState
        let returns = Fix1105Count()
        let retries = Fix1105Count()
        let (paths, feed) = AsyncStream.makeStream(of: Path.self)
        let watch = AssistantNetworkWatch(
            paths: paths, settle: .milliseconds(50), retry: { retries.value += 1 }, cameBack: { returns.value += 1 }
        )
        defer { watch.stop() }
        let wifi = Path(usable: true, interface: .wifi)
        let flagged = Path(usable: true, interface: .wifi, expensive: true)
        feed.yield(wifi)
        for _ in 0..<3 {
            feed.yield(flagged)
            feed.yield(wifi)
        }
        #expect(await eventually { retries.value == 1 }, "the marks may still be tried once")
        try await Task.sleep(for: .milliseconds(200))
        #expect(returns.value == 0, "back where it was: ParentLocker's import wait isn't restarted")

        // One that holds is a move: a phone's hotspot over Wi-Fi.
        feed.yield(flagged)
        #expect(await eventually { returns.value == 1 })
        // And back off it, once that holds too.
        feed.yield(wifi)
        #expect(await eventually { returns.value == 2 })
    }

    @Test("W10: a real move between Wi-Fi and cellular is still a move, even straight back", .timeLimit(.minutes(1)))
    func realMovesStillCount() async {
        typealias Path = AssistantNetworkWatch.PathState
        let returns = Fix1105Count()
        let (paths, feed) = AsyncStream.makeStream(of: Path.self)
        let watch = AssistantNetworkWatch(
            paths: paths, settle: .milliseconds(50), retry: {}, cameBack: { returns.value += 1 }
        )
        defer { watch.stop() }
        feed.yield(Path(usable: true, interface: .wifi))
        feed.yield(Path(usable: true, interface: .cellular, expensive: true))
        feed.yield(Path(usable: true, interface: .wifi))
        #expect(await eventually { returns.value == 1 }, "the link changed kind: requests on it may have died")
        feed.yield(Path(usable: false, interface: .other))
        feed.yield(Path(usable: true, interface: .wifi, expensive: true))
        #expect(await eventually { returns.value == 2 }, "back from no network, onto a hotspot")
    }

    // MARK: - W11: another sheet in any foreground window

    @Test("W11: the sign-in waits for a sheet in any foreground window, the key window or not")
    func anotherSheetInAnyForegroundWindow() {
        typealias Look = AssistantArrivalBar.SceneLook
        #expect(Bar.anotherSheetIsUp(in: [Look(state: .foregroundActive, presenting: [false, true])]),
                "a window that isn't key yet as the app becomes active")
        #expect(Bar.anotherSheetIsUp(in: [Look(state: .foregroundInactive, presenting: [true])]))
        #expect(!Bar.anotherSheetIsUp(in: [Look(state: .background, presenting: [true])]))
        #expect(!Bar.anotherSheetIsUp(in: [Look(state: .foregroundActive, presenting: [false, false])]))
        #expect(!Bar.anotherSheetIsUp(in: []))
    }
}
