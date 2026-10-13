import Foundation
import Testing
@testable import Daybook_Assistant

/// Close Arrival & Send's Undo on a phone that isn't signed in to ParentLocker
/// (bug check 2026-10-13, D2): it stays in reach, still stops the send, and
/// the sign-in sheet waits until its moment has passed.
@Suite("Assistant Close Arrival & Send Undo")
@MainActor
struct AssistantArrivalUndoTests {

    @Test("Signed in: the Undo stops the send and goes with it")
    func signedInUndoGoesWithTheSend() throws {
        let undo = try #require(AssistantArrivalBar.undo(afterClosing: 3, queuedSend: true, signedIn: true))
        #expect(undo.count == 3)
        #expect(undo.sendsToParentLocker, "times out when the class goes")
        #expect(undo.stopsSend)
        #expect(AssistantArrivalBar.afterUndoWindow(signedIn: true) == .hideUndo)
    }

    @Test("Not signed in: the Undo stays, still stops the send, and the sheet comes after it")
    func notSignedInKeepsTheUndo() throws {
        let undo = try #require(AssistantArrivalBar.undo(afterClosing: 3, queuedSend: true, signedIn: false))
        #expect(!undo.sendsToParentLocker, "nothing goes until she signs in, so the Undo doesn't time out")
        #expect(undo.stopsSend, "Undo still takes back the send waiting for the sign-in")
        #expect(AssistantArrivalBar.afterUndoWindow(signedIn: false) == .keepUndo)
        // The sheet waits out the Undo's moment (`signInPrompt`, bug hunt
        // 2026-10-13 afternoon, L2, in AssistantParentLockerAfternoonTests).
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let undoEnds = now.addingTimeInterval(ParentLockerSync.closeArrivalUndoWindow)
        #expect(AssistantArrivalBar.signInPrompt(
            awaitsSignIn: true, needsSignIn: true, undoEndsAt: undoEnds, asked: false, now: now
        ) == .at(undoEnds))
    }

    // Review of the bug-check fixes, D2: on a phone not signed in the Undo
    // never went.
    @Test("Not signed in: the Undo goes once the day is sent or after two minutes")
    func notSignedInUndoEnds() throws {
        typealias Bar = AssistantArrivalBar
        let closedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let later = closedAt.addingTimeInterval(10)
        #expect(Bar.afterUndoWindow(signedIn: false, closedAt: closedAt, now: later) == .keepUndo)
        #expect(Bar.afterUndoWindow(signedIn: false, daySent: true, closedAt: closedAt, now: later)
                == .hideUndo, "the guide's backstop sent the day")
        let limit = closedAt.addingTimeInterval(Bar.unsentUndoLimit)
        #expect(Bar.afterUndoWindow(signedIn: false, closedAt: closedAt, now: limit) == .hideUndo)
        #expect(Bar.unsentUndoLimit > ParentLockerSync.backstopWait)
        #expect(Bar.afterUndoWindow(signedIn: true, closedAt: closedAt, now: later) == .hideUndo)
    }

    @Test("A plain Close Arrival's Undo has no send to stop")
    func plainCloseArrival() throws {
        let undo = try #require(AssistantArrivalBar.undo(afterClosing: 2, queuedSend: false, signedIn: true))
        #expect(!undo.sendsToParentLocker)
        #expect(!undo.stopsSend)
        #expect(AssistantArrivalBar.undo(afterClosing: 0, queuedSend: true, signedIn: false) == nil, "no one to undo")
    }
}
