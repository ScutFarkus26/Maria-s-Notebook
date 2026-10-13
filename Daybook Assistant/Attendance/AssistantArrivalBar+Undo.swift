import Foundation

// Close Arrival & Send's Undo, as values: what it stops, how long a phone
// not signed in keeps it, and what happens once its moment has passed
// (`AssistantArrivalBar.watchUndo` follows them on screen). Also when the
// sign-in opens for a send waiting on it (`watchSignIn`), which follows the
// sync rather than the Undo.

extension AssistantArrivalBar {

    /// The Undo after closing arrival with `count` marked absent. With a
    /// ParentLocker send queued, Undo stops it (`stopsSend`); only a phone
    /// signed in sends when the Undo's moment passes, so only its Undo goes
    /// then (`sendsToParentLocker`). Nil when nobody was marked.
    static func undo(afterClosing count: Int, queuedSend: Bool, signedIn: Bool) -> ArrivalUndo? {
        guard count > 0 else { return nil }
        return ArrivalUndo(count: count, sendsToParentLocker: queuedSend && signedIn, stopsSend: queuedSend)
    }

    /// How long a phone not signed in keeps Close Arrival & Send's Undo:
    /// past the guide's 60-s backstop, which sends the day from his device,
    /// after which her Undo would only clear the absences here.
    static let unsentUndoLimit: TimeInterval = 120

    /// What happens once Close Arrival & Send's Undo moment has passed.
    enum AfterUndoWindow: Equatable {
        /// The class has gone to ParentLocker: Undo can't take it back.
        case hideUndo
        /// Nothing has gone (not signed in): the Undo stays until the limit.
        case keepUndo
    }

    /// Signed in, the day read as sent to ParentLocker (by anyone), or the
    /// Undo kept `unsentUndoLimit` since arrival closed: it goes. Otherwise
    /// it stays, and the sign-in opens by itself (`signInPrompt`).
    static func afterUndoWindow(
        signedIn: Bool, daySent: Bool = false, closedAt: Date = Date(), now: Date = Date()
    ) -> AfterUndoWindow {
        signedIn || daySent || now.timeIntervalSince(closedAt) >= unsentUndoLimit ? .hideUndo : .keepUndo
    }

    /// When the sign-in opens by itself.
    enum SignInPrompt: Equatable {
        case none
        case now
        /// Once Close Arrival & Send's Undo has had its moment, so the sheet
        /// never covers it.
        case at(Date)
    }

    /// The sign-in opens for a whole-class send waiting on it (Close Arrival
    /// & Send, Send to ParentLocker), once per send, after the Undo's
    /// moment (bug check 2026-10-13, D2). It follows the sync's waiting send,
    /// not the Undo (bug hunt 2026-10-13 afternoon, L2): the Undo goes when
    /// the app leaves the foreground, so a phone locked during it never
    /// asked. `asked`: the sheet closed without a sign-in while this send waited.
    static func signInPrompt(
        awaitsSignIn: Bool, needsSignIn: Bool, undoEndsAt: Date?, asked: Bool, now: Date
    ) -> SignInPrompt {
        guard awaitsSignIn, needsSignIn, !asked else { return .none }
        if let undoEndsAt, undoEndsAt > now { return .at(undoEndsAt) }
        return .now
    }
}

/// The Undo offered after closing arrival.
struct ArrivalUndo: Equatable {
    let id = UUID()
    let count: Int
    /// Close Arrival & Send on a phone signed in: the class goes once the
    /// Undo's moment passes, and the Undo goes with it.
    var sendsToParentLocker = false
    /// A ParentLocker send waits on this close: Undo stops it too. On a phone
    /// not signed in, the Undo stays past its moment and still stops it.
    var stopsSend = false
    /// When arrival closed: the Undo's moment counts from here.
    var closedAt = Date()
}
