import SwiftUI

// MARK: - Close Arrival & Send's Undo

extension AssistantArrivalBar {

    /// The day on screen reads as sent to ParentLocker: a send record, from
    /// this phone or synced in (the guide's backstop).
    private var daySentToParentLocker: Bool {
        viewModel.isToday && viewModel.frontDesk.latestSend?.channel == .parentLocker
    }

    /// What `watchUndo` follows: the Undo on offer, the sign-in, whether the
    /// send is still to go, and the day's send.
    var undoWatch: String {
        let sync = bootstrapper.parentLockerForScreens
        return "\(undo?.id.uuidString ?? "")|\(sync?.needsSignIn == false)"
            + "|\(sync?.closeArrivalSendUnsent == true)|\(daySentToParentLocker)"
    }

    /// The Undo can be tapped: no send under way (`undoEnabled`).
    var undoTappable: Bool { Self.undoEnabled(for: bootstrapper.parentLockerForScreens) }

    /// When this Undo stops being safe (bug check 2026-10-13, D2): the
    /// sync's "Undo ends at", when the send goes; without one, Close
    /// Arrival's own Undo window from the close.
    private func undoEnds(for undo: ArrivalUndo) -> Date {
        bootstrapper.parentLockerForScreens?.undoEndsAt
            ?? undo.closedAt.addingTimeInterval(ParentLockerSync.closeArrivalUndoWindow)
    }

    /// Waits out Close Arrival & Send's Undo, then hides it (signed in: the
    /// class has gone). Not signed in, or signed in with the send still to
    /// go, the Undo stays until she signs in, some of the class goes or the
    /// day reads as sent, each of which runs this again, or until
    /// `unsentUndoLimit`; the sign-in opens by itself meanwhile (`watchSignIn`).
    func watchUndo() async {
        guard let undo, undo.stopsSend else { return }
        let wait = undoEnds(for: undo).timeIntervalSinceNow
        if wait > 0 { guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return } }
        guard self.undo?.id == undo.id else { return }
        let after = Self.afterUndoWindow(
            signedIn: bootstrapper.parentLockerForScreens?.needsSignIn == false,
            sendUnsent: bootstrapper.parentLockerForScreens?.closeArrivalSendUnsent == true,
            daySent: daySentToParentLocker, closedAt: undo.closedAt, now: Date()
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
    /// Undo's end and the sheet; `AssistantTaskWhileActive` adds the app
    /// being in front.
    var signInWatch: String {
        let sync = bootstrapper.parentLockerForScreens
        return "\(sync?.awaitsSignIn == true)|\(sync?.needsSignIn == true)"
            + "|\(sync?.undoEndsAt?.timeIntervalSinceReferenceDate ?? 0)"
            + "|\(askedToSignIn)|\(showingSignIn)"
    }

    /// Opens the sign-in for a whole-class send waiting on it, once the
    /// Undo's moment has passed (`signInPrompt`): a phone locked during the
    /// Undo asks when it's back in front (bug hunt 2026-10-13 afternoon, L2).
    /// `isActive`: the app is in front.
    func watchSignIn(isActive: Bool) async {
        guard isActive, !showingSignIn, let sync = bootstrapper.parentLockerForScreens else { return }
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
        guard next == .now else { return }
        // Not over another sheet (the email, a note, the classroom): SwiftUI
        // shows one at a time, and the sign-in asked for under one never
        // opened and stayed asked for, so it never asked again (bug hunt
        // 2026-11-05, #25). It opens once that one has closed.
        guard await Self.waitWhileAnotherSheetIsUp(isUp: { Self.anotherSheetIsUp() }),
              !showingSignIn, prompt(at: Date()) == .now else { return }
        showingSignIn = true
    }

    /// Waits while `isUp` says another sheet is up, looking again `every`;
    /// true once none is, false if the wait was cancelled.
    static func waitWhileAnotherSheetIsUp(
        every: Duration = .seconds(1), isUp: () -> Bool
    ) async -> Bool {
        while isUp() {
            guard (try? await Task.sleep(for: every)) != nil else { return false }
        }
        return !Task.isCancelled
    }

    /// What `anotherSheetIsUp` reads of one scene: how it stands, and for
    /// each of its windows whether it shows something over its screens.
    struct SceneLook: Equatable {
        let state: UIScene.ActivationState
        let presenting: [Bool]
    }

    /// Whether the app's windows show something over its screens: a sheet,
    /// a full-screen cover, or a question.
    static func anotherSheetIsUp() -> Bool {
        anotherSheetIsUp(in: UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.map { scene in
            SceneLook(
                state: scene.activationState,
                presenting: scene.windows.map { $0.rootViewController?.presentedViewController != nil }
            )
        })
    }

    /// Any window of a scene in the foreground, active or becoming so,
    /// counts, the key window or not: as the app becomes active there may be
    /// no key window yet, and a sheet up then read as none (review of the
    /// 2026-11-05 fixes, W11). A scene in the background shows nothing.
    static func anotherSheetIsUp(in scenes: [SceneLook]) -> Bool {
        scenes.contains { scene in
            (scene.state == .foregroundActive || scene.state == .foregroundInactive) && scene.presenting.contains(true)
        }
    }

    /// The sign-in closed. Without a sign-in, it doesn't open by itself again
    /// for the send waiting now.
    func signInClosed() {
        guard let sync = bootstrapper.parentLockerForScreens, sync.needsSignIn else { return }
        askedToSignIn = sync.awaitsSignIn
        sync.signInDismissed()
    }
}

/// Runs `action` again whenever `id` changes or the app comes to or leaves
/// the front, telling it whether the app is in front. A modifier of its own,
/// like `AssistantReloadOnReturn`, so the scene phase is read here: read in
/// the arrival bar's body, every one of the four changes on a trip away and
/// back drew the whole bar again (bug hunt 2026-11-03, #24).
struct AssistantTaskWhileActive: ViewModifier {
    let id: String
    let action: (_ isActive: Bool) async -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let isActive = scenePhase == .active
        content.task(id: "\(id)|\(isActive)") { await action(isActive) }
    }
}
