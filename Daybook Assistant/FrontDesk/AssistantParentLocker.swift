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
    func offersParentLockerSend(by viewModel: AssistantAttendanceViewModel) -> Bool {
        offersParentLocker(by: viewModel) && latestSend == nil && viewModel.unmarkedCount == 0
    }

    /// Whether Close Arrival sends the class to ParentLocker as well: picked,
    /// today (other days go by Send Now), and the class's sync running here
    /// (never on the Sample Class).
    func closesWithSend(by viewModel: AssistantAttendanceViewModel, hasSync: Bool) -> Bool {
        hasSync && sendsToParentLocker && viewModel.isToday
    }
}

// MARK: - Sending after Siri closes arrival

/// What Siri's Close Arrival needs of the sync, so tests can stand in for it.
@MainActor
protocol AssistantParentLockerSending: AnyObject {
    var isSignedIn: Bool { get }
    func sendNow(day: Date) async -> ParentLockerStatus
    func closeArrivalSend(on day: Date, after undoWindow: TimeInterval)
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
}

extension AssistantSiriCommands {

    /// After Siri closes arrival: sends the whole class to ParentLocker when
    /// the guide picked it and this iPhone is signed in, and says how it went.
    /// Not signed in, the send waits for her to sign in (or the guide's
    /// backstop), as Close Arrival & Send does on screen. `sync` is the
    /// class's (`ParentLockerSync.current`); nil when it isn't running (the
    /// app launched for Siri alone), when the send is kept in `unsent` for
    /// the sync to make once it starts.
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
        guard sync.isSignedIn else {
            // Siri offers no Undo, so nothing to wait out.
            sync.closeArrivalSend(on: session.today, after: 0)
            return .notSignedIn
        }
        switch await sync.sendNow(day: session.today).state {
        case .upToDate: return .sent
        case .previewed: return .previewed
        default: return .notSentYet
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
        }
    }
}
