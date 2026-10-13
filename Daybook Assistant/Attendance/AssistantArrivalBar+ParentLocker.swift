import SwiftUI

// MARK: - Close Arrival & Send's Undo

extension AssistantArrivalBar {

    /// The day on screen reads as sent to ParentLocker: a send record, from
    /// this phone or synced in (the guide's backstop).
    private var daySentToParentLocker: Bool {
        viewModel.isToday && viewModel.frontDesk.latestSend?.channel == .parentLocker
    }

    /// What `watchUndo` follows: the Undo on offer, the sign-in, and the day's send.
    var undoWatch: String {
        "\(undo?.id.uuidString ?? "")|\(bootstrapper.parentLockerForScreens?.needsSignIn == false)"
            + "|\(daySentToParentLocker)"
    }

    /// When this Undo stops being safe (bug check 2026-10-13, D2): the
    /// sync's "Undo ends at", when the send goes; without one, Close
    /// Arrival's own Undo window from the close.
    private func undoEnds(for undo: ArrivalUndo) -> Date {
        bootstrapper.parentLockerForScreens?.undoEndsAt
            ?? undo.closedAt.addingTimeInterval(ParentLockerSync.closeArrivalUndoWindow)
    }

    /// Waits out Close Arrival & Send's Undo, then hides it (signed in: the
    /// class has gone). Not signed in, the Undo stays until she signs in or
    /// the day reads as sent, each of which runs this again, or until
    /// `unsentUndoLimit`; the sign-in opens by itself meanwhile (`watchSignIn`).
    func watchUndo() async {
        guard let undo, undo.stopsSend else { return }
        let wait = undoEnds(for: undo).timeIntervalSinceNow
        if wait > 0 { guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return } }
        guard self.undo?.id == undo.id else { return }
        let after = Self.afterUndoWindow(
            signedIn: bootstrapper.parentLockerForScreens?.needsSignIn == false, daySent: daySentToParentLocker,
            closedAt: undo.closedAt, now: Date()
        )
        if after == .keepUndo {
            let left = undo.closedAt.addingTimeInterval(Self.unsentUndoLimit).timeIntervalSinceNow
            if left > 0 { guard (try? await Task.sleep(for: .seconds(left))) != nil else { return } }
            guard self.undo?.id == undo.id else { return }
        }
        withAnimation(.smooth(duration: 0.3)) { self.undo = nil }
    }
}

// MARK: - Signing in for a waiting send

extension AssistantArrivalBar {

    /// What `watchSignIn` follows: the sync's waiting send and sign-in, the
    /// Undo's end, the sheet, and the app being in front.
    var signInWatch: String {
        let sync = bootstrapper.parentLockerForScreens
        return "\(sync?.awaitsSignIn == true)|\(sync?.needsSignIn == true)"
            + "|\(sync?.undoEndsAt?.timeIntervalSinceReferenceDate ?? 0)"
            + "|\(askedToSignIn)|\(showingSignIn)|\(scenePhase == .active)"
    }

    /// Opens the sign-in for a whole-class send waiting on it, once the
    /// Undo's moment has passed (`signInPrompt`): a phone locked during the
    /// Undo asks when it's back in front (bug hunt 2026-10-13 afternoon, L2).
    func watchSignIn() async {
        guard scenePhase == .active, !showingSignIn, let sync = bootstrapper.parentLockerForScreens else { return }
        func prompt(at now: Date) -> SignInPrompt {
            Self.signInPrompt(
                awaitsSignIn: sync.awaitsSignIn, needsSignIn: sync.needsSignIn,
                undoEndsAt: sync.undoEndsAt, asked: askedToSignIn, now: now
            )
        }
        var next = prompt(at: Date())
        if case .at(let time) = next {
            guard (try? await Task.sleep(for: .seconds(time.timeIntervalSinceNow))) != nil else { return }
            next = prompt(at: max(Date(), time))
        }
        if next == .now { showingSignIn = true }
    }

    /// The sign-in closed. Without a sign-in, it doesn't open by itself again
    /// for the send waiting now.
    func signInClosed() {
        guard let sync = bootstrapper.parentLockerForScreens, sync.needsSignIn else { return }
        askedToSignIn = sync.awaitsSignIn
        // MERGE (agent E's sign-in dismissal hook; wire at merge): sync.signInDismissed()
    }
}
