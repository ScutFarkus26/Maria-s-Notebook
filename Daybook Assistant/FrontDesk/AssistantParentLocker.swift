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

    /// Whether the line offers Send to ParentLocker: everyone's marked, so
    /// there's no Close Arrival to send the day, and nobody has sent it.
    /// A child left out of ParentLocker ("Not matched") isn't waited for,
    /// as the sync's line doesn't (`AttendanceRow.waitsForParentLocker`).
    func offersParentLockerSend(by viewModel: AssistantAttendanceViewModel) -> Bool {
        offersParentLocker(by: viewModel) && latestSend == nil
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
    /// A Debug build or a test run: it read ParentLocker and saved nothing.
    case previewed
    /// This iPhone isn't signed in to ParentLocker.
    case notSignedIn
    /// It couldn't reach ParentLocker, or the class's sync wasn't running.
    case notSentYet
    /// ParentLocker isn't expecting the class's attendance today.
    case notExpected
}

extension AssistantSiriCommands {

    /// After Siri closes arrival: sends the whole class to ParentLocker when
    /// the guide picked it and this iPhone is signed in, and says how it went.
    /// It goes as Close Arrival & Send's, so a send that fails and waits to
    /// try again is still one Siri's "Undo that" stops (review of the
    /// afternoon fixes, H2). Not signed in, the send waits for her to sign
    /// in (or the guide's backstop), as Close Arrival & Send does on screen.
    /// `sync` is the class's (`ParentLockerSync.current`); nil when it isn't
    /// running (the app launched for Siri alone), when the send is kept in
    /// `unsent` for the sync to make once it starts.
    static func sendAfterClose(
        _ session: SiriAttendance, sync: (any AssistantParentLockerSending)?,
        unsent: any ParentLockerUnsentStore = ParentLockerSync.defaultUnsentStore()
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
        switch await sync.closeArrivalSendNow(on: session.today).state {
        case .upToDate: return .sent
        case .previewed: return .previewed
        case .notExpected: return .notExpected
        default: return .notSentYet
        }
    }

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
        case .previewed: closed + " This test copy of the app doesn't send to ParentLocker."
        case .notSignedIn:
            closed + " Attendance hasn't gone to ParentLocker yet. "
                + "Open the Assistant and sign in to ParentLocker to send it."
        case .notSentYet:
            closed + " Attendance hasn't gone to ParentLocker yet. Open the Assistant to send it."
        case .notExpected:
            closed + " " + ParentLockerStatus.notExpectedLine
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
    case send
    /// Not signed in, today: the sync keeps the send for once she signs in,
    /// and the sign-in opens, so one tap is enough (L6).
    case sendAfterSignIn
    /// Not signed in, another day: only the sign-in. A send waiting for a
    /// sign-in is for today only.
    case signIn

    /// The first step of a send of `day`. `unmarkedConfirmed`: she has
    /// answered the question about the unmarked children.
    static func first(
        on day: Date, isToday: Bool, unmarkedConfirmed: Bool, sync: any AssistantParentLockerSending
    ) -> Self {
        if !unmarkedConfirmed {
            let unmarked = sync.unmarkedNames(on: day)
            if !unmarked.isEmpty { return .ask(unmarked: unmarked) }
        }
        guard sync.needsSignIn else { return .send }
        return isToday ? .sendAfterSignIn : .signIn
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
