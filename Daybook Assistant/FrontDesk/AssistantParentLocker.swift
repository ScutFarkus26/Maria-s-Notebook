import Foundation

// ParentLocker on the Assistant (plan "ParentLocker attendance", Phase 4).
// When the guide picks ParentLocker in the notebook, the front-desk email
// steps aside: Close Arrival becomes Close Arrival & Send, the bar shows the
// shared status line with Send Now, and the Classroom sheet has her sign-in.
// The sending itself is the shared engine's (`ParentLockerSync`), started on
// the real class by the bootstrapper and never on the Sample Class.

extension AssistantFrontDesk {

    /// The guide picked ParentLocker as the way attendance goes.
    var sendsToParentLocker: Bool { settings?.sendMethod == .parentLocker }

    /// Whether the bar shows the ParentLocker line: ParentLocker picked, and
    /// the day has a class that has arrived (not a day off or a day ahead).
    func offersParentLocker(by viewModel: AssistantAttendanceViewModel) -> Bool {
        sendsToParentLocker && viewModel.dayOff == nil && !viewModel.rows.isEmpty && !viewModel.isFuture
    }

    /// Whether the line offers Send to ParentLocker: today, everyone's
    /// marked, so there's no Close Arrival to send the day, and nobody has
    /// sent it. A child left out of ParentLocker ("Not matched") isn't
    /// waited for, as the sync's line doesn't (`AttendanceRow.waitsForParentLocker`).
    /// Not another day (bug hunt 2026-10-20, #17): every school day from
    /// before send records began showed it, and one tap sent a month-old day
    /// over what the office had; those keep Send Now in the line's menu,
    /// which asks first. Not on a day ParentLocker isn't expecting (#19).
    func offersParentLockerSend(by viewModel: AssistantAttendanceViewModel) -> Bool {
        offersParentLocker(by: viewModel) && viewModel.isToday && latestSend == nil && !isNotExpected
            && !viewModel.rows.contains(where: \.waitsForParentLocker)
    }

    /// Whether Close Arrival sends the class to ParentLocker as well: picked,
    /// today (other days go by Send Now), and the class's sync running here
    /// (never on the Sample Class).
    func closesWithSend(by viewModel: AssistantAttendanceViewModel, hasSync: Bool) -> Bool {
        hasSync && sendsToParentLocker && viewModel.isToday
    }
}

// MARK: - Sending after Siri closes arrival

/// What Siri's Close Arrival and its Undo, and the bar's Send Now, need of
/// the sync, so tests can stand in for it.
@MainActor
protocol AssistantParentLockerSending: AnyObject {
    var isSignedIn: Bool { get }
    /// Not signed in, or signed in with a password ParentLocker refused.
    var needsSignIn: Bool { get }
    /// Today's Close Arrival & Send is still to go and none of it has gone
    /// (`ParentLockerSync.closeArrivalSendUnsent`).
    var closeArrivalSendUnsent: Bool { get }
    func sendNow(day: Date) async -> ParentLockerStatus
    func closeArrivalSend(on day: Date, after undoWindow: TimeInterval)
    func closeArrivalSendNow(on day: Date) async -> ParentLockerStatus
    func cancelCloseArrivalSend()
    func unmarkedNames(on day: Date) -> [String]
}

extension ParentLockerSync: AssistantParentLockerSending {}

/// How ParentLocker went after Siri closed arrival.
enum AssistantParentLockerAfterClose: Equatable {
    /// Attendance goes by email (or nothing is set up): nothing to say.
    case notPicked
    case sent
    /// It went, but some children need a look: the status has lines about
    /// particular children (locked, not matched, changed by someone else).
    case sentWithProblems
    /// A Debug build or a test run: it read ParentLocker and saved nothing.
    case previewed
    /// This iPhone isn't signed in to ParentLocker, or its saved password
    /// was refused, or ParentLocker wants a person to sign in.
    case notSignedIn
    /// Still going when Siri's wait ran out (`siriSendWait`): it keeps going.
    case onItsWay
    /// It couldn't reach ParentLocker, and a retry is due by itself, which
    /// may not come while the app is in the background.
    case retrying
    /// ParentLocker's page isn't what the app knows: opening the app won't fix it.
    case pageChanged
    /// ParentLocker answered with an error of its own: its site is where to look.
    case refused
    /// None of the class was found in ParentLocker, most likely a sign-in
    /// with another account: the Assistant's sign-in is where to look.
    case noneFound
    /// This iPhone couldn't use its saved sign-in.
    case keychainTrouble
    /// It couldn't send, or the class's sync wasn't running: opening the app sends it.
    case notSentYet
    /// It didn't go, for a reason the Assistant's line explains (arrival
    /// open again, say).
    case notSent
    /// ParentLocker isn't expecting the class's attendance today.
    case notExpected
    /// Some of the class may be in ParentLocker, but the send stopped on
    /// this before all of it went (review of the 2026-11-05 fixes, W7).
    indirect case partlySent(AssistantParentLockerAfterClose)
}

extension AssistantSiriCommands {

    /// The longest Siri waits for the send before answering (bug hunt
    /// 2026-11-05, #7). Siri gives an intent about 30 s before it may cancel
    /// it, and on slow school Wi-Fi a send can take longer than that: Siri
    /// gave up with its own error while the send carried on. Its Undo waits
    /// as long for a send under way (`SiriAttendance.parentLockerWait`).
    static let siriSendWait = SiriAttendance.parentLockerWait

    /// After Siri closes arrival: sends the whole class to ParentLocker when
    /// the guide picked it and this iPhone is signed in, and says how it went.
    /// It goes as Close Arrival & Send's, so a send that fails and waits to
    /// try again is still one Siri's "Undo that" stops (review of the
    /// afternoon fixes, H2). Not signed in, the send waits for her to sign
    /// in (or the guide's backstop), as Close Arrival & Send does on screen.
    /// `sync` is the class's (`ParentLockerSync.current`); nil when it isn't
    /// running (the app launched for Siri alone), when the send is kept in
    /// `unsent` for the sync to make once it starts.
    ///
    /// Siri waits for the send `waitsAtMost` (`siriSendWait`), then answers
    /// that it's on its way (#7). The send runs in a task of its own that
    /// the wait never cancels, and the sync records the day when it lands.
    static func sendAfterClose(
        _ session: SiriAttendance, sync: (any AssistantParentLockerSending)?,
        unsent: any ParentLockerUnsentStore = ParentLockerSync.defaultUnsentStore(),
        waitsAtMost wait: Duration = siriSendWait
    ) async -> AssistantParentLockerAfterClose {
        // Siri marks the real class unless the app was launched into the
        // sample (`AssistantStack`), whatever the join screen has open.
        guard !AssistantSampleClass.isRequested,
              AttendanceEmailLog.settings(in: session.context)?.sendMethod == .parentLocker else { return .notPicked }
        guard let sync else {
            ParentLockerSync.oweCloseArrivalSend(on: session.today, in: unsent)
            return .notSentYet
        }
        // A password ParentLocker refused is never tried again by itself
        // (bug hunt 2026-10-13 afternoon, L5): it needs her sign-in too.
        guard !sync.needsSignIn else {
            // Siri offers no Undo, so nothing to wait out.
            sync.closeArrivalSend(on: session.today, after: 0)
            return .notSignedIn
        }
        let day = session.today
        let send = Task { await sync.closeArrivalSendNow(on: day) }
        guard let status = await value(of: send, orNilAfter: wait) else { return .onItsWay }
        return afterClose(status, unsent: sync.closeArrivalSendUnsent)
    }

    /// What Siri says of a send that ended on `status` (bug hunt 2026-11-05,
    /// #17; review of its fixes, W7 and W8): each way it ends has its own
    /// answer, and only what opening the app fixes says to open it. A
    /// changed page or a refusal needs the ParentLocker site, a sign-in
    /// problem her sign-in. `unsent`: none of Close Arrival's send has gone
    /// (the sync's `closeArrivalSendUnsent`); a failure after part of it
    /// went is `partlySent`, never "hasn't gone".
    static func afterClose(_ status: ParentLockerStatus, unsent: Bool = true) -> AssistantParentLockerAfterClose {
        let outcome = outcome(of: status)
        return SiriAttendance.closeArrivalPartlySent(state: status.state, unsent: unsent)
            ? .partlySent(outcome) : outcome
    }

    // The answer for each way a send ends, one to one.
    // swiftlint:disable:next cyclomatic_complexity
    private static func outcome(of status: ParentLockerStatus) -> AssistantParentLockerAfterClose {
        switch status.state {
        case .upToDate: status.problems.isEmpty ? .sent : .sentWithProblems
        case .previewed: .previewed
        case .notExpected: .notExpected
        // Attendance goes by email after all: nothing to say about ParentLocker.
        case .off: .notPicked
        case .retrying: .retrying
        case .pageChanged: .pageChanged
        case .refused: .refused
        case .keychainTrouble: .keychainTrouble
        case .waitingForSignIn, .signedOut, .passwordRefused, .needsYou: .notSignedIn
        case .gaveUp, .notSentYet: .notSentYet
        // A whole-class send that found none of the class ends quiet, with
        // that as its problem (`ParentLockerSync.finish`).
        case .idle where !status.problems.isEmpty: .noneFound
        default: .notSent
        }
    }

    /// `task`'s value, or nil if `limit` passes first. Either way the task is
    /// left alone, never cancelled: it's the send, and it keeps going. A
    /// task group's race wouldn't do, as the send awaits a task of its own
    /// (a group waits for its children, and cancelling it stops the send).
    static func value<Value: Sendable>(
        of task: Task<Value, Never>, orNilAfter limit: Duration
    ) async -> Value? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
            let answer = FirstAnswer(continuation)
            let timer = Task {
                try? await Task.sleep(for: limit)
                answer.give(nil)
            }
            Task {
                let value = await task.value
                timer.cancel()
                answer.give(value)
            }
        }
    }
}

/// Resumes its continuation with the first answer given, once.
@MainActor
private final class FirstAnswer<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) { self.continuation = continuation }

    func give(_ value: Value?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

extension AssistantSiriCommands {

    /// Siri's Undo of its Close Arrival: the send it left waiting doesn't go
    /// (bug hunt 2026-10-13 afternoon, H2). The running sync's Close Arrival
    /// & Send is cancelled, and arrival is open again there; with no sync
    /// running (the app launched for Siri alone), the send kept in `unsent`
    /// for launch and its "arrival closed here" go, so a later sign-in never
    /// sends the reopened class. A class that has already gone stays gone:
    /// ParentLocker can't take a mark back (`SiriAttendance.undoLast` says so).
    static func undoCloseSend(
        on day: Date, sync: (any AssistantParentLockerSending)?,
        unsent: any ParentLockerUnsentStore = ParentLockerSync.defaultUnsentStore()
    ) {
        guard !AssistantSampleClass.isRequested else { return }
        if let sync {
            sync.cancelCloseArrivalSend()
        } else {
            ParentLockerSync.cancelOwedCloseArrivalSend(on: day, in: unsent)
        }
    }

    /// What Siri says once arrival is closed: how many it marked, then how
    /// ParentLocker went, if it's how attendance goes.
    static func closedDialog(marked count: Int, parentLocker: AssistantParentLockerAfterClose) -> String {
        let closed = count == 0
            ? "Arrival is closed. Everyone was already marked."
            : "Arrival is closed. \(count) \(count == 1 ? "child is" : "children are") marked absent."
        return switch parentLocker {
        case .notPicked: closed
        case .sent: closed + " Attendance went to ParentLocker."
        case .sentWithProblems:
            closed + " Attendance went to ParentLocker, but some children need a look. Open the Assistant to see who."
        case .previewed: closed + " This test copy of the app doesn't send to ParentLocker."
        case .onItsWay: closed + " Attendance is on its way to ParentLocker."
        case .notExpected: closed + " " + ParentLockerStatus.notExpectedLine
        case .noneFound:
            closed + " None of the class's children were found in ParentLocker, so nothing went. "
                + "Open the Assistant and check that it's signed in with your school's ParentLocker account."
        case .notSent: closed + " Attendance didn't go to ParentLocker. Open the Assistant to see why."
        // After part of the class went, never "hasn't gone" (review of the 2026-11-05 fixes, W7).
        case .partlySent(let stopped):
            closed + " Some of today's attendance may already be in ParentLocker, but not all of it went. "
                + stillToGo(stopped, rest: true)
        default: closed + " Attendance hasn't gone to ParentLocker yet. " + stillToGo(parentLocker, rest: false)
        }
    }

    /// What a send that hasn't all gone needs, by how it stopped: what
    /// happened, then what to do, if anything. `rest`: part of it went.
    private static func stillToGo(_ stopped: AssistantParentLockerAfterClose, rest: Bool) -> String {
        let what = rest ? "the rest" : "it"
        return switch stopped {
        case .notSignedIn: "Open the Assistant and sign in to ParentLocker to send \(what)."
        // Not "in a moment": with the app in the background, the retry may
        // wait until it's opened (W7).
        case .retrying:
            "It couldn't reach ParentLocker\(rest ? " for the rest" : "") and will try again by itself. "
                + "If \(what) still hasn't gone in a few minutes, open the Assistant to send it."
        case .pageChanged: "ParentLocker's page has changed. Take attendance on the ParentLocker site for now."
        case .refused: "ParentLocker didn't take it. Check today's attendance on the ParentLocker site."
        case .keychainTrouble:
            "This iPhone couldn't use its saved ParentLocker sign-in. Restart the iPhone, then open the "
                + "Assistant to send \(what)."
        default: "Open the Assistant to send \(what)."
        }
    }
}

// MARK: - Send Now on screen

/// What the bar's Send Now (and Send to ParentLocker) does first.
enum AssistantParentLockerSendStep: Equatable {
    /// Children aren't marked yet: ask first, naming them (bug hunt
    /// 2026-10-13 afternoon, M4). The sync sends the marked ones and doesn't
    /// count the day as sent.
    case ask(unmarked: [String])
    /// Another day, signed in: ask first, naming anyone unmarked there. Its
    /// send replaces what the office has for that day, so it's never one
    /// tap (bug hunt 2026-10-20, #17).
    case confirmDay(unmarked: [String])
    case send
    /// Not signed in, today: the sync keeps the send for once she signs in,
    /// and the sign-in opens, so one tap is enough (L6).
    case sendAfterSignIn
    /// Not signed in, another day: only the sign-in. A send waiting for a
    /// sign-in is for today only.
    case signIn

    /// The first step of a send of `day`. `unmarkedConfirmed`: she has
    /// answered the question about the unmarked children; `dayConfirmed`,
    /// another day's question.
    static func first(
        on day: Date, isToday: Bool, unmarkedConfirmed: Bool, dayConfirmed: Bool = false,
        sync: any AssistantParentLockerSending
    ) -> Self {
        if !dayConfirmed, confirmsDay(isToday: isToday), !sync.needsSignIn {
            return .confirmDay(unmarked: sync.unmarkedNames(on: day))
        }
        if !unmarkedConfirmed {
            let unmarked = sync.unmarkedNames(on: day)
            if !unmarked.isEmpty { return .ask(unmarked: unmarked) }
        }
        guard sync.needsSignIn else { return .send }
        return isToday ? .sendAfterSignIn : .signIn
    }

    /// Whether Send Now asks before sending the day on screen: another day's
    /// send replaces what the office has for it, so it's never one tap (bug
    /// hunt 2026-10-20, #17). Today's goes as before.
    static func confirmsDay(isToday: Bool) -> Bool { !isToday }

    /// A question Send Now asked, and the day it asked about. Her answer
    /// sends that day: the bar used to send whichever day was on screen when
    /// she answered (review of the 2026-10-20 fixes).
    struct Question: Equatable {
        let day: Date
        let isToday: Bool
        /// `.ask` or `.confirmDay`.
        let step: AssistantParentLockerSendStep

        /// The children the question names.
        var unmarked: [String] {
            switch step {
            case .ask(let unmarked), .confirmDay(let unmarked): unmarked
            default: []
            }
        }

        /// What her yes does next, for the day asked about. Another day's
        /// question named its unmarked children too, so it answers both.
        func answered(sync: any AssistantParentLockerSending) -> AssistantParentLockerSendStep {
            let dayConfirmed = if case .confirmDay = step { true } else { false }
            return first(
                on: day, isToday: isToday, unmarkedConfirmed: true, dayConfirmed: dayConfirmed, sync: sync
            )
        }
    }

    /// The question's title: "Ari isn't marked yet", "3 children aren't marked yet".
    static func question(unmarked: [String]) -> String {
        unmarked.count == 1 ? "\(unmarked[0]) isn't marked yet" : "\(unmarked.count) children aren't marked yet"
    }

    /// The question's words, naming them.
    static func questionMessage(unmarked: [String]) -> String {
        "\(unmarked.formatted(.list(type: .and))) \(unmarked.count == 1 ? "isn't" : "aren't") marked. "
            + "Everyone else goes to ParentLocker now. Mark them and send again to finish the day."
    }
}
