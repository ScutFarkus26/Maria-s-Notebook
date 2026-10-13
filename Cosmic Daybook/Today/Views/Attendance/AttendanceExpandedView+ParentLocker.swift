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
    /// signed in asks to sign in; the send waits for it.
    func sendAfterClosingArrival() -> (() -> Void)? {
        guard sendsToParentLocker, viewModel.isToday, let sync = parentLocker else { return nil }
        sync.closeArrivalSend(on: date, after: undoWindow)
        if !sync.isSignedIn { showingParentLockerSignIn = true }
        return { sync.cancelCloseArrivalSend() }
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
    @ViewBuilder
    func parentLockerSendButton(overdue: Bool, prominent: Bool) -> some View {
        let menu = Menu {
            Button("Mark as Sent", systemImage: "checkmark.circle") { recordFrontDeskSend(confirmedByHand: true) }
        } label: {
            Label("Send to ParentLocker", systemImage: "paperplane")
        } primaryAction: {
            sendToParentLockerNow()
        }
        .help("Send this day's attendance to ParentLocker")
        if prominent {
            menu.buttonStyle(.borderedProminent).tint(overdue ? .orange : nil)
        } else {
            menu.buttonStyle(.bordered)
        }
    }

    /// What's due: "front desk email", or "ParentLocker attendance".
    var dueWhat: String { sendsToParentLocker ? "ParentLocker attendance" : "front desk email" }

    /// Send Now: the whole class for the day on screen, now; or the sign-in
    /// sheet first.
    func sendToParentLockerNow() {
        guard let sync = parentLocker else { return }
        guard sync.isSignedIn else {
            showingParentLockerSignIn = true
            return
        }
        let day = date
        let toasts = dependencies.toastService
        Task {
            let status = await sync.sendNow(day: day)
            parentLockerSynced()
            switch status.state {
            case .upToDate:
                toasts.showSuccess("Sent to ParentLocker")
            case .previewed:
                toasts.showInfo("This test copy of the app only previews. Nothing was sent to ParentLocker.")
            default:
                if let message = status.message { toasts.showError(message) }
            }
        }
    }

    /// The ⋯ menu's ParentLocker items: Send Now, Mark as Sent for a day
    /// taken on the site by hand, and Sign In while not signed in.
    @ViewBuilder
    var parentLockerMenuItems: some View {
        Section("ParentLocker") {
            Button(frontDeskSend == nil ? "Send Now" : "Send Again", systemImage: "paperplane",
                   action: sendToParentLockerNow)
            if frontDeskSend == nil {
                Button("Mark as Sent", systemImage: "checkmark.circle") { recordFrontDeskSend(confirmedByHand: true) }
            }
            if parentLocker?.isSignedIn == false {
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

    /// The sign-in sheet, and the send record and reminder after each sync.
    var parentLockerFollowUps: ParentLockerFollowUps {
        ParentLockerFollowUps(
            sync: parentLocker,
            context: viewContext,
            showingSignIn: $showingParentLockerSignIn,
            sendMethod: $loadedSendMethod,
            onSynced: parentLockerSynced
        )
    }
}

/// The roll's follow-ups to ParentLocker, as a modifier so its body stays
/// one line there.
struct ParentLockerFollowUps: ViewModifier {
    let sync: ParentLockerSync?
    let context: NSManagedObjectContext
    @Binding var showingSignIn: Bool
    /// The roll's method, followed as the shared settings row changes: an
    /// edit in Settings (the Mac's own window, beside the roll) or one synced
    /// in from the guide's other devices.
    @Binding var sendMethod: AttendanceSendMethod?
    let onSynced: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingSignIn) {
                if let sync { ParentLockerSignInSheet(sync: sync) }
            }
            .onPresentationDataChangeWhenVisible(of: ["AttendanceEmailSettings"], in: context, catchUpOnAppear: false) {
                sendMethod = AttendanceExpandedView.sendMethod(in: context)
            }
            .onChange(of: sync?.status.lastSyncAt) { _, synced in
                if synced != nil { onSynced() }
            }
    }
}
