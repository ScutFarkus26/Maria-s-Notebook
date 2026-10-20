import Foundation
import CloudKit
import OSLog

// Rebuilding the stack without losing what's under way (bug hunt 2026-10-20):
// a join running on the old stack (#8), the screen she's on (#22), and the
// class store's own failed setup (#9). And after "Download from iCloud
// again", the wait for a joined phone's membership to come back down (#13).

extension AssistantBootstrapper {
    private static let rebuildLogger = Logger.app(category: "bootstrap")

    // MARK: - Where the stacks come from

    /// The stacks a rebuild opens, the open one, its filing hold, and the
    /// join screen's Sample Class: the app's own (`live`), or a test's.
    struct Stacks {
        var rebuild: @MainActor () throws -> CoreDataStack
        var current: @MainActor () -> CoreDataStack?
        var filingHold: @MainActor () -> AssistantFilingHold?
        var sample: @MainActor () throws -> CoreDataStack
        /// The app's own: a rebuilt stack starts its ParentLocker sync and
        /// asks iCloud who she is (`install`). A test's doesn't.
        var isLive = false

        static var live: Stacks {
            Stacks(
                rebuild: { try AssistantStack.rebuild() },
                current: { AssistantStack.current },
                filingHold: { AssistantStack.filingHold },
                sample: { try AssistantSampleClass.savedStack() },
                isLive: true
            )
        }
    }

    // MARK: - A join under way

    /// Waits while a join's accept runs on the stack about to be rebuilt, up
    /// to `limit`: rebuilt under it, the join was lost and she stayed on
    /// "Waiting for the invitation…" (#8). An accept timed out on screen
    /// still runs, and is waited for too. Returns the invitation to accept
    /// again on the new stack, once per invitation: one whose join failed
    /// meanwhile, or one still running at the limit, whose old accept is let
    /// go of (`letGoOfJoin`). The join's own timeout used to end the wait at
    /// once, so only a join that failed quickly was kept (2026-10-20 review
    /// b, item 2).
    func waitForJoinBeforeRebuild(
        on service: ClassroomSharingService?,
        upTo limit: Duration = ClassroomSharingService.joinTimeout
    ) async -> CKShare.Metadata? {
        guard let service, service.acceptIsRunning else { return nil }
        Self.rebuildLogger.notice("A join is running; the rebuild waits for it")
        // An invitation already accepted again once fails as usual instead.
        let invitation = service.runningInvitation
        let mayKeep = invitation.map { $0.share.recordID != rejoinedInvitation } ?? false
        service.keepsFailedInvitation = mayKeep
        defer { service.keepsFailedInvitation = false }
        let deadline = ContinuousClock.now + limit
        while service.acceptIsRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard mayKeep, let invitation else { return nil }
        if let failed = service.failedInvitation {
            rejoinedInvitation = failed.share.recordID
            Self.rebuildLogger.notice("The join failed on the old stack; it goes again on the rebuilt one")
            return failed
        }
        // Joined meanwhile.
        guard service.acceptIsRunning else { return nil }
        service.letGoOfJoin()
        rejoinedInvitation = invitation.share.recordID
        Self.rebuildLogger.notice("The join is still running at the limit; it goes again on the rebuilt stack")
        return invitation
    }

    // MARK: - The screen during a rebuild

    /// Whether a rebuild shows "Starting…": only on a phone that has joined
    /// (its class open, or a download waiting for its membership). The join
    /// screen and the Sample Class stay up instead, so setup keeps its page
    /// (#22), and the sample isn't swapped out under her.
    nonisolated static func rebuildShowsStarting(ready: Bool, starting: Bool, inSample: Bool) -> Bool {
        (ready && !inSample) || starting
    }

    var isStartingPhase: Bool {
        if case .starting = phase { true } else { false }
    }

    /// Whether the Sample Class opens again after a relaunch or a rebuild:
    /// only on the join screen, and not while a join runs, whose progress
    /// the join screen shows (bug hunt 2026-10-20 #21).
    nonisolated static func reopensSample(needsClassroom: Bool, joining: Bool) -> Bool {
        needsClassroom && !joining
    }

    // MARK: - The class store's failed setup

    /// Follows the open stack's filing hold for a setup that failed without
    /// a usable account, including one that failed before this listened.
    func followFailedSetup() {
        guard let hold = stacks.filingHold() else { return }
        hold.onSetupFailedForAccount = { [weak self] in
            Task { await self?.rebuildIfSetupFailed() }
        }
        if hold.setupFailedForAccount { Task { await rebuildIfSetupFailed() } }
    }

    /// The class store's setup failed without an account, and the account
    /// is here now: rebuilt (#9). The account check alone missed it when its
    /// first answer came after she signed in, or couldn't tell, so the store
    /// stayed unable to send her marks.
    ///
    /// Each stack's own failed setup counts, the stack rebuilt when the
    /// account arrived included: its setup can fail the same way while the
    /// account settles, and a "once a launch" spent on that rebuild, or on
    /// one that never ran because another was running, left her marks unsent
    /// until a relaunch (2026-10-20 review b, item 1). A failure heard while
    /// a rebuild runs is looked at when it ends (`rebuildStack`). A second
    /// rebuild for a failed setup within `failedSetupRebuildWindow` gives up,
    /// as a mirroring stop does: the sync line says to quit and reopen.
    func rebuildIfSetupFailed() async {
        guard coreDataStack != nil, !isRebuilding else { return }
        switch Self.failedSetupResponse(
            setupFailed: stacks.filingHold()?.setupFailedForAccount ?? false,
            status: accountStatus,
            rebuiltRecently: rebuiltForFailedSetupRecently
        ) {
        case .ignore:
            break
        case .rebuild:
            rebuiltForFailedSetupAt = now()
            await rebuildStack(because: "The class's iCloud setup failed without an account; the account is here")
        case .giveUp:
            guard !sendingStopped else { return }
            Self.rebuildLogger.error("The rebuilt stack's iCloud setup failed again; sending waits for a relaunch")
            sendingStopped = true
        }
    }

    enum FailedSetupResponse: Equatable {
        case ignore, rebuild, giveUp
    }

    /// What the class store's setup failing for want of an account calls
    /// for: nothing until the account is available, then a rebuild, unless
    /// one for the same reason ran recently.
    nonisolated static func failedSetupResponse(
        setupFailed: Bool, status: CKAccountStatus?, rebuiltRecently: Bool
    ) -> FailedSetupResponse {
        guard setupFailed, status == .available else { return .ignore }
        return rebuiltRecently ? .giveUp : .rebuild
    }

    /// A failed setup this soon after the last rebuild for one counts as the
    /// rebuilt stack failing too.
    nonisolated static let failedSetupRebuildWindow: TimeInterval = 10 * 60

    private var rebuiltForFailedSetupRecently: Bool {
        guard let last = rebuiltForFailedSetupAt else { return false }
        return now().timeIntervalSince(last) < Self.failedSetupRebuildWindow
    }

    // MARK: - Waiting for the membership after a download

    /// How long "Starting…" waits for a joined phone's membership after
    /// "Download from iCloud again" before the join screen shows.
    nonisolated static let membershipWaitLimit: Duration = .seconds(90)

    /// After each membership read while one is awaited: found, the wait
    /// ends; not yet, the limit starts, once. Past it, she's on the join
    /// screen: the class may have let her go meanwhile.
    func noteMembershipRead(hasMembership: Bool) {
        guard awaitsMembership else { return }
        if hasMembership {
            awaitsMembership = false
            AssistantClassroomLocalState.membershipAwaited()
            membershipWait?.cancel()
            membershipWait = nil
            return
        }
        guard membershipWait == nil else { return }
        membershipWait = Task { [weak self] in
            try? await Task.sleep(for: Self.membershipWaitLimit)
            guard let self, !Task.isCancelled, awaitsMembership else { return }
            membershipWait = nil
            awaitsMembership = false
            AssistantClassroomLocalState.membershipAwaited()
            Self.rebuildLogger.notice("The class's membership didn't come back; showing the join screen")
            refreshMembership()
        }
    }
}
