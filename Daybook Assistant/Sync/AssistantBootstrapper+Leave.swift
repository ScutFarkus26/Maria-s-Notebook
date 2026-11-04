import Foundation
import CoreData
import OSLog

// Leave Classroom, here or on another of her iPhones, and the marks not yet
// sent when she leaves.

extension AssistantBootstrapper {
    private static let leaveLogger = Logger.app(category: "bootstrap")

    /// Leaves the classroom: the class comes off this iPhone and the screen
    /// goes back to joining. Her marks stay with the guide. Taken out of the
    /// class, the share read at launch is gone: Leave reads the store afresh.
    ///
    /// Nothing goes into the share while it runs: it waits for the running
    /// attach, and the marks still waiting are deleted once the class is off
    /// (`giveUpWaitingMarks`), so none goes into the next class she joins.
    ///
    /// A share call stuck past the watchdog never lets the attacher go idle,
    /// so "Try Leave again in a minute" refused for good: only quitting and
    /// reopening the app ends it, and Leave says so (2026-10-20 review b,
    /// item 3).
    func leaveClassroom() async throws {
        let attacher = AssistantShareAttacher.shared
        guard !attacher.sendingLooksStuck else { throw AssistantLeaveError.sendingStuck }
        // Taken out of the class, there's no share of hers to purge: the pin
        // may name a class she has joined since, which Leave purged (bug
        // hunt 2026-11-02 #6). Read before the wait.
        let classIsGone = removedFromClass
        isLeavingHere = true
        attacher.hold()
        defer {
            attacher.release()
            isLeavingHere = false
            settleDeferredStop()
        }
        guard await attacher.waitUntilIdle(upTo: Self.leaveWaitLimit) else {
            throw attacher.sendingLooksStuck ? AssistantLeaveError.sendingStuck : AssistantLeaveError.stillSending
        }
        if classIsGone, !removedFromClass {
            // Joined a class while this waited: "Not in This Class" is over,
            // and its Leave isn't the new class's.
            Self.leaveLogger.notice("Joined a class while Leave waited; nothing was left")
            return
        }
        if classIsGone { sharingService?.updateShareState(nil) }
        try await sharingService?.leaveClassroom(classroomIsGone: classIsGone)
        // Nothing came off (no service yet, or a row it wouldn't leave): the
        // class and its waiting marks stay.
        guard !hasOwnMembership() else { return }
        await giveUpWaitingMarks(attacher.pending)
        await backToJoining()
    }

    /// Leave on another of her iPhones deletes the membership rows, and the
    /// deletion reaches this one by sync. Nothing followed it: this iPhone
    /// stayed on a class it had left. Now it goes back to joining, as if she
    /// had left here; CloudKit takes the class's copy off by itself.
    func followLeaveElsewhere() async {
        guard coreDataStack != nil else { return }
        guard Self.leftElsewhere(hasOwnRow: hasOwnMembership(), leavingHere: isLeavingHere) else { return }
        Self.leaveLogger.notice("Left the classroom on another device; back to joining")
        await dropWaitingMarks()
        await backToJoining()
    }

    /// Whether this iPhone's own membership row is here; true with no stack
    /// to read, which can't say it's gone.
    func hasOwnMembership() -> Bool {
        guard let context = coreDataStack?.viewContext else { return true }
        let request = CDClassroomMembership.ownRowsRequest()
        request.fetchLimit = 1
        return context.safeFetchFirst(request) != nil
    }

    /// After a Leave, here or elsewhere: this iPhone's classroom state and
    /// reminders go, and the screen goes back to joining.
    func backToJoining() async {
        removedFromClass = false
        // View only was that class's: the next one says for itself (#29).
        sharingService?.noteViewOnly(false)
        ClassroomPermissions.shareIsViewOnly = false
        AssistantClassroomLocalState.forget()
        // What ParentLocker owed for that class goes; the sign-in stays (bug hunt 2026-11-03 #21).
        parentLocker?.classLeft()
        await ArrivalReminder.cancelAll()
        await FrontDeskEmailReminder.cancelAll()
        await EarlyPickupReminder.cancelAll()
        refreshMembership()
    }

    // MARK: - Leaving with marks not sent

    /// Marks this iPhone holds that haven't reached the guide: some waiting
    /// to go into the share (counted), or an edit iCloud hasn't uploaded yet.
    /// A new mark is the share step's to count, so it's never uncounted.
    /// Only attendance marks are counted as marks; her Restock changes and
    /// front-desk sends are "other changes" (bug hunt 2026-11-02 #43).
    enum UnsentMarks: Equatable {
        case counted(Int, otherChanges: Bool = false)
        /// Only changes that aren't marks wait for the share.
        case otherChanges
        case uncounted

        var message: String {
            let what = switch self {
            case .counted(1, otherChanges: false): "1 mark hasn't reached your guide yet."
            case .counted(let count, otherChanges: false): "\(count) marks haven't reached your guide yet."
            case .counted(1, otherChanges: true): "1 mark and other changes haven't reached your guide yet."
            case .counted(let count, otherChanges: true):
                "\(count) marks and other changes haven't reached your guide yet."
            case .otherChanges: "Some of your changes haven't reached your guide yet."
            case .uncounted: "Your latest marks haven't reached your guide yet."
            }
            return what + " If you leave now, they're lost. Wait tries to send them first."
        }
    }

    nonisolated static func unsentMarks(
        waitingForShare: Int, otherChanges: Int = 0, unsentSave: Bool
    ) -> UnsentMarks? {
        if waitingForShare > 0 { return .counted(waitingForShare, otherChanges: otherChanges > 0) }
        if otherChanges > 0 { return .otherChanges }
        return unsentSave ? .uncounted : nil
    }

    /// What Leave would lose now. Leave purges the class at once, so marks
    /// still on their way never reached the guide. A save is unsent while
    /// the keep-alive says so, or while the sync line's record has no upload
    /// begun after it: the keep-alive starts empty at each launch, so marks
    /// saved before a relaunch and never uploaded went unwarned (bug hunt
    /// 2026-10-20 #12).
    func unsentMarks() -> UnsentMarks? {
        let waiting = AssistantShareAttacher.shared.waitingByKind()
        return Self.unsentMarksNow(
            waitingForShare: waiting.marks,
            otherChanges: waiting.otherChanges,
            keepAlive: AssistantStack.keepAlive,
            syncRecord: AssistantStack.syncRecord
        )
    }

    /// `unsentMarks()` from the pieces it reads: the tests pass their own.
    static func unsentMarksNow(
        waitingForShare: Int,
        otherChanges: Int = 0,
        keepAlive: UnsentChangesKeepAlive?,
        syncRecord: AssistantSyncRecord?
    ) -> UnsentMarks? {
        unsentMarks(
            waitingForShare: waitingForShare,
            otherChanges: otherChanges,
            unsentSave: (keepAlive?.hasUnsentWork ?? false) || (syncRecord?.hasUnsentSave ?? false)
        )
    }

    /// Sending can't go on until the app is reopened: mirroring stopped
    /// again after its rebuild, or a share call is stuck past the watchdog.
    /// The sync line, Leave and Leave's Wait all say to quit and reopen.
    var sendingNeedsRelaunch: Bool {
        sendingStopped || AssistantShareAttacher.shared.sendingLooksStuck
    }

    /// Leave's Wait: tries the waiting marks now and gives them up to
    /// `limit` to go. Returns what's still unsent.
    func sendUnsentMarks(upTo limit: Duration = .seconds(25)) async -> UnsentMarks? {
        await Self.sendUnsentMarks(
            attacher: AssistantShareAttacher.shared,
            keepAlive: AssistantStack.keepAlive,
            syncRecord: AssistantStack.syncRecord,
            sendingStopped: sendingStopped,
            upTo: limit
        )
    }

    /// `sendUnsentMarks(upTo:)` with the pieces it uses; the tests pass their
    /// own. Stuck or stopped, nothing goes until the app is reopened, so it
    /// doesn't spin (2026-10-20 review b, item 3). A save from
    /// before a relaunch, which the keep-alive doesn't know of, waits for its
    /// upload too: Wait used to return at once and say it hadn't gone (item 7).
    static func sendUnsentMarks(
        attacher: AssistantShareAttacher,
        keepAlive: UnsentChangesKeepAlive?,
        syncRecord: AssistantSyncRecord?,
        sendingStopped: Bool,
        upTo limit: Duration
    ) async -> UnsentMarks? {
        let unsent = {
            let waiting = attacher.waitingByKind()
            return unsentMarksNow(
                waitingForShare: waiting.marks, otherChanges: waiting.otherChanges,
                keepAlive: keepAlive, syncRecord: syncRecord
            )
        }
        guard !sendingStopped, !attacher.sendingLooksStuck else { return unsent() }
        let deadline = ContinuousClock.now + limit
        attacher.retryWaiting()
        while attacher.isRunning, !attacher.sendingLooksStuck, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
        await keepAlive?.waitUntilSent(upTo: max(.zero, deadline - ContinuousClock.now))
        while syncRecord?.hasUnsentSave == true, !attacher.sendingLooksStuck, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return unsent()
    }

    /// What Leave's Wait says when it's done: the marks went; sending is
    /// stuck, which only reopening the app ends (it said "Check that this
    /// iPhone is online", item 3); or some are still on their way. Under a
    /// filing hold Wait tries nothing, and returned at once telling an
    /// online iPhone to check it was online (bug hunt 2026-11-02 #45): a
    /// dead delegate needs a relaunch, and iCloud not set up yet says so.
    nonisolated static func afterWaitNote(
        stillUnsent: Bool, needsRelaunch: Bool, filingWait: AssistantFilingHold.Wait?
    ) -> String {
        guard stillUnsent else { return "Your marks have reached your guide. You can leave now." }
        if needsRelaunch || filingWait == .mirroringDied {
            return "Your marks aren't sending. Quit the app and open it again, then leave."
        }
        if filingWait == .iCloudNotReady {
            return "iCloud isn't ready on this iPhone yet, so your marks haven't gone. Wait a minute, then try again."
        }
        return "Some marks still haven't gone. Check that this iPhone is online, then try again."
    }

    /// `afterWaitNote` for this iPhone now.
    func noteAfterWait(stillUnsent: Bool) -> String {
        Self.afterWaitNote(
            stillUnsent: stillUnsent, needsRelaunch: sendingNeedsRelaunch, filingWait: AssistantStack.filingWait
        )
    }

    /// How long Leave waits for a running attach before saying to try again.
    nonisolated static let leaveWaitLimit: Duration = .seconds(20)
}

/// Why Leave didn't start, said on the Classroom screen.
enum AssistantLeaveError: LocalizedError {
    /// Her marks were still going into the class's share when she tapped
    /// Leave, and still were after `leaveWaitLimit`.
    case stillSending
    /// A share call is stuck past the watchdog (`sendingLooksStuck`): it
    /// never ends while the app runs.
    case sendingStuck

    var errorDescription: String? {
        switch self {
        case .stillSending:
            "Your marks are still on their way to your guide, so nothing was removed. Try Leave again in a minute."
        case .sendingStuck:
            "Your marks aren't sending, so nothing was removed. Quit the app and open it again, then leave."
        }
    }
}
