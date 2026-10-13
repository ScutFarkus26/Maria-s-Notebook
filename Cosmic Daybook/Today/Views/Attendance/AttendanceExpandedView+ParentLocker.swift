// AttendanceExpandedView+ParentLocker.swift
// The roll with ParentLocker picked (plan "ParentLocker attendance", Phase 3):
// the one status line, Close Arrival & Send (the class goes once Close
// Arrival's Undo has gone; Undo stops it), Send Now, and the sign-in sheet
// for a device that isn't signed in yet.

import CoreData
import SwiftUI

extension AttendanceExpandedView {

    /// How the guide sends the day's attendance, as the shared settings row
    /// holds it: what the sync, the reminder, MCP and the assistants read.
    /// Not the synced preference, which reaches the row only after Settings
    /// writes it: a screen reading the preference offered Close Arrival &
    /// Send while the sync still saw email, and sent nothing (bug check
    /// 2026-10-13, C1).
    var sendMethod: AttendanceSendMethod { loadedSendMethod ?? Self.sendMethod(in: viewContext) }

    /// The method in the shared settings row; email before there is one.
    static func sendMethod(in context: NSManagedObjectContext) -> AttendanceSendMethod {
        AttendanceEmailLog.settings(in: context)?.sendMethod ?? .email
    }

    /// The sync for this class; none in the Sample Class.
    var parentLocker: ParentLockerSync? { ParentLockerSync.current(for: viewContext) }

    /// ParentLocker is how the day goes, and this class has the sync.
    var sendsToParentLocker: Bool { sendMethod == .parentLocker && parentLocker != nil }

    /// The front-desk email is how the day goes, and it's turned on.
    var emailIsOn: Bool { emailEnabled && sendMethod == .email }

    /// The day still has to go to ParentLocker.
    var parentLockerIsOpen: Bool { sendsToParentLocker && !isNonSchoolDay && frontDeskSend == nil }

    /// "Sent to ParentLocker 8:47 AM by Sarah · up to date": the day's send,
    /// and for today where this device's sync stands.
    @ViewBuilder
    func parentLockerLine(showsProblems: Bool) -> some View {
        if sendsToParentLocker, !viewModel.isFuture, !isNonSchoolDay || frontDeskSend != nil {
            ParentLockerStatusLine(
                status: viewModel.isToday ? parentLocker?.status ?? ParentLockerStatus() : ParentLockerStatus(),
                sentSummary: frontDeskSend.map(frontDeskSummary),
                showsProblems: showsProblems
            )
        }
    }

    // MARK: - Close Arrival & Send

    /// The toast after Close Arrival, which says the class is about to go.
    func closeArrivalToast(count: Int) -> String {
        let marked = count == 1 ? "Marked 1 absent" : "Marked \(count) absent"
        guard sendsToParentLocker, viewModel.isToday else { return marked }
        return marked + ". Sending to ParentLocker unless you undo."
    }

    /// Close Arrival & Send: the whole class goes once the Undo toast just
    /// shown has gone. Returns what Undo calls to stop it. A device not
    /// signed in asks to sign in once that Undo has gone, never over it (bug
    /// hunt 2026-10-13 afternoon, M1, as the Daybook Assistant's bar does);
    /// the send waits for the sign-in.
    func sendAfterClosingArrival() -> (() -> Void)? {
        guard sendsToParentLocker, viewModel.isToday, let sync = parentLocker else { return nil }
        sync.closeArrivalSend(on: date, after: undoWindow)
        // Not signed in, or the saved password was refused: sign in again.
        if let delay = Self.signInDelay(after: sync), let undoEnds = sync.undoEndsAt {
            let showingSignIn = $showingParentLockerSignIn
            Task {
                if delay > 0 { guard (try? await Task.sleep(for: .seconds(delay))) != nil else { return } }
                if Self.asksToSignIn(afterUndoEnding: undoEnds, sync: sync) { showingSignIn.wrappedValue = true }
            }
        }
        return { sync.cancelCloseArrivalSend() }
    }

    /// How long Close Arrival & Send waits before asking to sign in: until
    /// its Undo has gone. Nil when it won't ask: signed in, or no send waits.
    static func signInDelay(after sync: ParentLockerSync) -> TimeInterval? {
        guard sync.needsSignIn, let undoEnds = sync.undoEndsAt else { return nil }
        return max(0, undoEnds.timeIntervalSince(sync.clock.now))
    }

    /// Whether the sign-in opens once the Undo ending at `undoEnds` has gone:
    /// that Close Arrival & Send still waits (no Undo or Reset since), and
    /// this device still isn't signed in.
    static func asksToSignIn(afterUndoEnding undoEnds: Date, sync: ParentLockerSync) -> Bool {
        sync.undoEndsAt == undoEnds && sync.needsSignIn
    }

    /// How long until the Undo toast just shown has gone: its own time, after
    /// any toasts ahead of it, with a second to spare.
    private var undoWindow: TimeInterval {
        let toasts = dependencies.toastService
        let showing = (toasts.currentToast.map { [$0] } ?? []) + toasts.queuedToasts
        let wait = showing.reduce(0) { $0 + $1.duration + 0.5 } + 1
        return max(ParentLockerSync.closeArrivalUndoWindow, wait)
    }

    // MARK: - Send Now

    /// Send to ParentLocker (Send Now), for a day taken without Close
    /// Arrival; Mark as Sent in its menu for one taken on the site by hand.
    func parentLockerSendButton(overdue: Bool, prominent: Bool) -> some View {
        ParentLockerAsking { asker in
            let menu = Menu {
                Button("Mark as Sent", systemImage: "checkmark.circle") { recordFrontDeskSend(confirmedByHand: true) }
            } label: {
                Label("Send to ParentLocker", systemImage: "paperplane")
            } primaryAction: {
                sendToParentLockerNow(asking: asker)
            }
            .help("Send this day's attendance to ParentLocker")
            if prominent {
                menu.buttonStyle(.borderedProminent).tint(overdue ? .orange : nil)
            } else {
                menu.buttonStyle(.bordered)
            }
        }
    }

    /// What's due: "front desk email", or "ParentLocker attendance".
    var dueWhat: String { sendsToParentLocker ? "ParentLocker attendance" : "front desk email" }

    /// Send Now for the day on screen. With children unmarked it asks first,
    /// naming them (bug hunt 2026-10-13 afternoon, M4). `asker` is nil only
    /// where the roll's follow-ups don't reach, and then it just sends.
    func sendToParentLockerNow(asking asker: ParentLockerSendAsker?) {
        guard let sync = parentLocker else { return }
        if let asker, let question = ParentLockerSendQuestion.beforeSending(
            on: date, unmarked: sync.unmarkedNames(on: date)
        ) {
            asker.question = question
            return
        }
        sendToParentLocker(day: date)
    }

    /// The 9:00 reminder's tap with ParentLocker picked: asks whether to send
    /// today's attendance now, naming anyone unmarked (M2).
    func offerParentLockerSend(asking asker: ParentLockerSendAsker?) {
        guard let sync = parentLocker, let asker else { return }
        asker.question = .fromReminder(on: date, unmarked: sync.unmarkedNames(on: date))
    }

    /// The whole class for `day`, now. Not signed in: today's send waits in
    /// the sync for the sign-in the sheet opens for, so one tap is enough
    /// (L6); another day's is sent again once signed in.
    func sendToParentLocker(day: Date) {
        guard let sync = parentLocker else { return }
        let steps = Self.sendSteps(needsSignIn: sync.needsSignIn, isToday: sync.isToday(day))
        if steps.opensSignIn {
            if steps.sends {
                Task {
                    await sync.sendNow(day: day)
                    parentLockerSynced()
                }
            }
            showingParentLockerSignIn = true
            return
        }
        let toasts = dependencies.toastService
        Task {
            let status = await sync.sendNow(day: day)
            parentLockerSynced()
            switch Self.sendNowToast(for: status) {
            case .success(let text): toasts.showSuccess(text)
            case .info(let text): toasts.showInfo(text)
            case .error(let text): toasts.showError(text)
            case nil: break
            }
        }
    }

    /// What tapping Send does: signed in, it sends; not, it opens the
    /// sign-in, and for today also asks the sync to send once signed in.
    static func sendSteps(needsSignIn: Bool, isToday: Bool) -> (sends: Bool, opensSignIn: Bool) {
        needsSignIn ? (isToday, true) : (true, false)
    }

    /// Send Now's toast.
    enum SendNowToast: Equatable {
        case success(String)
        case info(String)
        case error(String)
    }

    /// What Send Now's toast says about how the send ended. A run that ends
    /// with nothing to say of its own ("None of the class's children were
    /// found in ParentLocker…") gives its first problem (M3).
    static func sendNowToast(for status: ParentLockerStatus) -> SendNowToast? {
        switch status.state {
        case .upToDate:
            return .success("Sent to ParentLocker")
        case .previewed:
            return .info("This test copy of the app only previews. Nothing was sent to ParentLocker.")
        default:
            if let message = status.message { return .error(message) }
            return status.problems.first.map(SendNowToast.error)
        }
    }

    /// The ⋯ menu's ParentLocker items: Send Now, Mark as Sent for a day
    /// taken on the site by hand, and Sign In while not signed in (or the
    /// saved password was refused).
    @ViewBuilder
    var parentLockerMenuItems: some View {
        Section("ParentLocker") {
            ParentLockerAsking { asker in
                Button(frontDeskSend == nil ? "Send Now" : "Send Again", systemImage: "paperplane") {
                    sendToParentLockerNow(asking: asker)
                }
            }
            if frontDeskSend == nil {
                Button("Mark as Sent", systemImage: "checkmark.circle") { recordFrontDeskSend(confirmedByHand: true) }
            }
            if parentLocker?.needsSignIn == true {
                Button("Sign In to ParentLocker…", systemImage: "person.crop.circle") {
                    showingParentLockerSignIn = true
                }
            }
        }
    }

    /// A send finished here (or the sync recorded one): the day's send and
    /// the reminder follow it.
    func parentLockerSynced() {
        frontDeskSend = AttendanceEmailLog.latestSend(on: date, in: viewContext)
        let context = viewContext
        Task { await FrontDeskEmailReminder.reschedule(in: context) }
    }

    /// The question before a send, the sign-in sheet, and the send record
    /// and reminder after each sync.
    var parentLockerFollowUps: ParentLockerFollowUps {
        ParentLockerFollowUps(
            sync: parentLocker,
            context: viewContext,
            showingSignIn: $showingParentLockerSignIn,
            sendMethod: $loadedSendMethod,
            onSynced: parentLockerSynced,
            onSend: { sendToParentLocker(day: $0) }
        )
    }
}

/// The roll's follow-ups to ParentLocker, as a modifier so its body stays
/// one line there. Its asker goes into the environment, for the buttons
/// that ask before a send (`ParentLockerAsking`) and the reminder's tap.
struct ParentLockerFollowUps: ViewModifier {
    let sync: ParentLockerSync?
    let context: NSManagedObjectContext
    @Binding var showingSignIn: Bool
    /// The roll's method, followed as the shared settings row changes: an
    /// edit in Settings (the Mac's own window, beside the roll) or one synced
    /// in from the guide's other devices.
    @Binding var sendMethod: AttendanceSendMethod?
    let onSynced: () -> Void
    /// Sends the day the question was about, once the guide says to.
    let onSend: (Date) -> Void

    @State private var asker = ParentLockerSendAsker()

    func body(content: Content) -> some View {
        content
            .environment(asker)
            .alert(
                asker.question?.title ?? "",
                isPresented: Binding(get: { asker.question != nil }, set: { if !$0 { asker.question = nil } }),
                presenting: asker.question
            ) { question in
                Button(question.sendTitle) { onSend(question.day) }
                Button("Cancel", role: .cancel) {}
            } message: { question in
                Text(question.message)
            }
            .sheet(isPresented: $showingSignIn, onDismiss: {
                // Closed without signing in: a waiting Send Now is dropped (L6).
                if let sync, sync.needsSignIn { sync.signInDismissed() }
            }, content: {
                if let sync { ParentLockerSignInSheet(sync: sync) }
            })
            .onPresentationDataChangeWhenVisible(of: ["AttendanceEmailSettings"], in: context, catchUpOnAppear: false) {
                sendMethod = AttendanceExpandedView.sendMethod(in: context)
            }
            .onChange(of: sync?.status.lastSyncAt) { _, synced in
                if synced != nil { onSynced() }
            }
    }
}

/// The question the roll asks before a send to ParentLocker: with children
/// unmarked, who (bug hunt 2026-10-13 afternoon, M4); from the 9:00
/// reminder, whether to send now (M2).
struct ParentLockerSendQuestion: Equatable {
    /// The day it would send.
    let day: Date
    let title: String
    let message: String
    /// The button that sends.
    let sendTitle: String

    /// Before Send Now: nil while everyone on the roll is marked.
    static func beforeSending(on day: Date, unmarked: [String]) -> ParentLockerSendQuestion? {
        guard !unmarked.isEmpty else { return nil }
        return ParentLockerSendQuestion(
            day: day,
            title: unmarked.count == 1 ? "1 child isn't marked yet" : "\(unmarked.count) children aren't marked yet",
            message: "\(unmarked.formatted(.list(type: .and))). Send the rest to ParentLocker now, or mark them first.",
            sendTitle: "Send the Rest"
        )
    }

    /// The 9:00 reminder's tap: today's attendance is due.
    static func fromReminder(on day: Date, unmarked: [String]) -> ParentLockerSendQuestion {
        beforeSending(on: day, unmarked: unmarked) ?? ParentLockerSendQuestion(
            day: day,
            title: "Send today's attendance to ParentLocker?",
            message: "Everyone's marked.",
            sendTitle: "Send"
        )
    }
}

/// Holds the roll's question before a send, for the buttons that ask
/// (`ParentLockerAsking`) and the alert that shows it (`ParentLockerFollowUps`).
@MainActor
@Observable
final class ParentLockerSendAsker {
    var question: ParentLockerSendQuestion?
}

/// Hands its content the roll's asker, from the environment
/// `ParentLockerFollowUps` sets: nil outside a roll.
struct ParentLockerAsking<Content: View>: View {
    @Environment(ParentLockerSendAsker.self) private var asker: ParentLockerSendAsker?
    @ViewBuilder let content: (ParentLockerSendAsker?) -> Content

    var body: some View { content(asker) }
}
