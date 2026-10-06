import Foundation
import CoreData
import CloudKit
import OSLog
import Observation

/// Builds the Core Data stack and sharing service, and tracks whether this
/// device has joined a classroom yet.
///
/// The lead guide's app has a long bootstrap of migrations, repairs and
/// backfills. None of it belongs here: the assistant's device owns no data of
/// its own, and every record it sees arrives through the accepted share.
@MainActor
@Observable
final class AssistantBootstrapper {

    private static let logger = Logger.app(category: "bootstrap")

    enum Phase {
        case starting
        case needsClassroom
        case ready
        case failed(AssistantStartupProblem)
    }

    private(set) var phase: Phase = .starting
    private(set) var coreDataStack: CoreDataStack?
    private(set) var sharingService: ClassroomSharingService?
    /// This iPhone's iCloud account as CloudKit sees it; nil until asked.
    /// Onboarding and the sync line name the problem when it isn't
    /// `.available`, instead of a generic "check iCloud" tip.
    private(set) var accountStatus: CKAccountStatus?

    @ObservationIgnored var acceptanceObserver: (any NSObjectProtocol)?
    @ObservationIgnored var accountObserver: Task<Void, Never>?
    @ObservationIgnored var nameObserver: (any NSObjectProtocol)?
    @ObservationIgnored var foregroundObserver: (any NSObjectProtocol)?
    @ObservationIgnored var remoteChangeObserver: Task<Void, Never>?
    /// Set when the first account check after building the stack found no
    /// usable iCloud account. `NSPersistentCloudKitContainer` fails its setup
    /// then, and although it later imports once the account appears, sharing
    /// stays broken for the life of the container: every new mark fails to
    /// attach to the classroom and sits at "Not sent yet" until the app is
    /// relaunched. So the stack is rebuilt when the account arrives.
    private var stackNeedsAccount = false
    /// Whether the account has been checked since the stack was built.
    private var accountCheckedSinceBuild = false
    /// Set while this iPhone's own Leave runs. Its membership delete comes
    /// back as a remote change, which `followLeaveElsewhere` read as a Leave
    /// on another device.
    private(set) var isLeavingHere = false
    /// Set while `start()` runs: launch and the window both start it.
    private var isStarting = false

    /// Asks CloudKit for the account's status; tests pass their own.
    @ObservationIgnored private let fetchAccountStatus: @MainActor () async throws -> CKAccountStatus
    /// Asks CloudKit who is signed in, after an account change.
    @ObservationIgnored let fetchUserRecordName: @MainActor () async throws -> String
    /// The account's record name as last read here, which an account change
    /// is compared with (`readAccountAgain`).
    @ObservationIgnored var knownRecordName: String?
    /// Another Apple Account signed in: the name here was the last one's,
    /// so she's asked for hers (`AssistantTabs`).
    var askForNameAgain = false
    /// A mirroring stop reported while the app was starting, failing or
    /// leaving, looked at again once it isn't (`settleDeferredStop`).
    @ObservationIgnored weak var deferredStop: NSPersistentCloudKitContainer?
    /// Numbers each account check: an answer that arrives after a newer one
    /// began is dropped (the slowest answer used to win, however old).
    @ObservationIgnored private var accountCheck = 0
    /// Mirroring stopped again after its one rebuild (`mirroringStopped(in:)`).
    var sendingStopped = false
    /// When the stack was last rebuilt because mirroring stopped: a second
    /// stop soon after gives up rather than rebuilding round and round, but
    /// one hours later, on a stack that worked meanwhile, gets its rebuild.
    @ObservationIgnored var rebuiltForMirroringStopAt: Date?
    /// Taken out of the class (`checkStillInClass`).
    var removedFromClass = false
    @ObservationIgnored var classCheck: Task<Void, Never>?
    @ObservationIgnored var classCheckAgain = false
    /// The history trim's export recorder, and whether this launch trimmed.
    @ObservationIgnored var exportRecorder: Task<Void, Never>?
    @ObservationIgnored var historyTrimmed = false

    init(
        fetchAccountStatus: @escaping @MainActor () async throws -> CKAccountStatus = {
            try await CloudKitConfigurationService.container.accountStatus()
        },
        fetchUserRecordName: @escaping @MainActor () async throws -> String = {
            try await CloudKitConfigurationService.container.userRecordID().recordName
        }
    ) {
        self.fetchAccountStatus = fetchAccountStatus
        self.fetchUserRecordName = fetchUserRecordName
    }

    func start() async {
        guard case .starting = phase, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        if AssistantSampleClass.isRequested {
            do {
                coreDataStack = try AssistantStack.shared()
                phase = .ready
            } catch {
                phase = .failed(AssistantStartupProblem(error, storesOpen: AssistantStack.isOpen))
            }
            return
        }

        // The sample was open when the app closed: it opens again below, with
        // its pickup reminders. Otherwise they outlive it, and come off.
        let reopenSample = AssistantSampleClass.wasOpen
        if !reopenSample { await EarlyPickupReminder.cancelSample() }

        do {
            // Shared with Siri, which may have opened it already.
            install(try AssistantStack.shared())
            restoreName()
            observeAcceptance()
            observeRemoteChanges()
            observeAccountChanges()
            observeReturnToForeground()
            observeMirroringStops()
            startHistoryUpkeep()
            if reopenSample { await resumeSample() }
        } catch {
            Self.logger.error("Assistant bootstrap failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(AssistantStartupProblem(error, storesOpen: AssistantStack.isOpen))
        }
    }

    /// Takes a newly built stack: its sharing service, and the phase its
    /// membership row gives.
    private func install(_ stack: CoreDataStack) {
        AssistantSampleClass.isChosen = false
        coreDataStack = stack
        let service = ClassroomSharingService(
            container: stack.container,
            context: stack.viewContext
        )
        sharingService = service
        accountCheckedSinceBuild = false
        stackNeedsAccount = false
        sendingStopped = false
        removedFromClass = false

        refreshMembership()
        // Who she is, for "you" on her marks, sends and Restock changes. Again
        // on each rebuild, which is when an iCloud account arrives late. Then
        // a name she gave before that was known joins the classroom's list.
        // Only once she's in the class: before, it was written at launch with
        // no class to write it to.
        Task {
            // Read before the refresh overwrites it: an account that changed
            // while the app was closed shows only here.
            let before = ClassroomIdentity.currentUserRecordName
            await ClassroomIdentity.refreshRecordName()
            noteAccountAtLaunch(before: before)
            if coreDataStack === stack { writeWaitingName() }
        }
    }

    /// Builds the stack again: once iCloud is signed in (see
    /// `stackNeedsAccount`), or once after CloudKit mirroring stopped
    /// (`mirroringStopped(in:)`). The screens let go of the old one first,
    /// so nothing reads its objects once its stores are gone, and a running
    /// attach finishes on it (`waitForAttachBeforeRebuild`).
    func rebuildStack(because reason: String) async {
        Self.logger.info("\(reason, privacy: .public); rebuilding the Core Data stack")
        phase = .starting
        sharingService = nil
        coreDataStack = nil
        let attacher = AssistantShareAttacher.shared
        attacher.hold()
        defer { attacher.release() }
        await waitForAttachBeforeRebuild(attacher)
        do {
            install(try AssistantStack.rebuild())
            await resumeSample()
        } catch {
            Self.logger.error("Assistant rebuild failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(AssistantStartupProblem(error, storesOpen: AssistantStack.isOpen))
        }
    }

    /// The "Can't start" screen's way out: delete this iPhone's copies of the
    /// class and download them again. Both stores are copies of iCloud, so
    /// only marks this iPhone hadn't sent yet are lost (the screen says so
    /// first). Safe to delete here: a failed start leaves no stack holding
    /// the files (`AssistantStack.shared()` keeps only one that loaded).
    ///
    /// If a stack is open by now, Siri opened the class since this start
    /// failed: it opens after all, so this starts again on that stack rather
    /// than delete files under it. (It used to return, and the button did
    /// nothing.)
    func rebuildFromICloud() async {
        guard case .failed(let problem) = phase, problem.canRebuild else { return }
        phase = .starting
        if AssistantStack.isOpen {
            Self.logger.notice("The class opened for Siri since the failed start; starting on that stack")
        } else {
            Self.logger.warning("Rebuilding the class from iCloud after a failed start")
            CoreDataStack.performLocalCacheReset()
            AssistantClassroomLocalState.forget()
            AssistantShareAttacher.shared.forgetWaiting()
        }
        await start()
    }

    /// Re-reads the membership row. Acceptance writes one, and the roster only
    /// starts arriving afterwards, so this is what flips onboarding to the
    /// attendance list.
    ///
    /// The sharing service reads the row again too. A row that arrives by sync
    /// after the service was built would otherwise leave it on `.leadGuide`:
    /// Leave Classroom did nothing, and the share was looked for in the
    /// private store, so the guide's name never showed.
    func refreshMembership() {
        guard let context = coreDataStack?.viewContext else { return }
        defer { settleDeferredStop() }
        let request = CDClassroomMembership.ownRowsRequest()
        request.fetchLimit = 1
        let hasMembership = context.safeFetchFirst(request) != nil
        let wasReady = if case .ready = phase { true } else { false }
        phase = hasMembership ? .ready : .needsClassroom
        // Marks an earlier Leave couldn't sort go before anything new is filed.
        Task { await deleteLeftBehindMarks() }
        guard let service = sharingService else { return }
        service.loadCurrentMembership()
        guard hasMembership, !wasReady else { return }
        if service.currentShare == nil {
            // Only joining fills in the share otherwise: the guide's name
            // on the Classroom screen, and "you" on her own marks.
            Task { await service.refreshShareInBackground() }
        }
        // Marks an earlier session couldn't put into the share try again.
        if let stack = coreDataStack {
            AssistantShareAttacher.shared.flush(container: stack.container, context: stack.viewContext)
        }
        checkStillInClass()
    }

    /// Leaves the classroom: the class comes off this iPhone and the screen
    /// goes back to joining. Her marks stay with the guide. Taken out of the
    /// class, the share read at launch is gone: Leave reads the store afresh.
    ///
    /// Nothing goes into the share while it runs: it waits for the running
    /// attach, and the marks still waiting are deleted once the class is off
    /// (`giveUpWaitingMarks`), so none goes into the next class she joins.
    func leaveClassroom() async throws {
        isLeavingHere = true
        let attacher = AssistantShareAttacher.shared
        attacher.hold()
        defer {
            attacher.release()
            isLeavingHere = false
            settleDeferredStop()
        }
        guard await attacher.waitUntilIdle(upTo: Self.leaveWaitLimit) else { throw AssistantLeaveError.stillSending }
        if removedFromClass { sharingService?.updateShareState(nil) }
        try await sharingService?.leaveClassroom()
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
        Self.logger.notice("Left the classroom on another device; back to joining")
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
    private func backToJoining() async {
        removedFromClass = false
        AssistantClassroomLocalState.forget()
        await ArrivalReminder.cancelAll()
        await FrontDeskEmailReminder.cancelAll()
        await EarlyPickupReminder.cancelAll()
        refreshMembership()
    }

    func refreshAccountStatus() async {
        accountCheck += 1
        let check = accountCheck
        let status: CKAccountStatus
        do {
            status = try await fetchAccountStatus()
        } catch {
            // Unknown isn't a problem worth showing; keep what we had.
            Self.logger.error("iCloud account status failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        // A newer check is on its way, and its answer is the one that counts.
        guard check == accountCheck else { return }
        accountStatus = status
        guard coreDataStack != nil else { return }
        let decision = Self.accountDecision(
            checkedSinceBuild: accountCheckedSinceBuild,
            needsAccount: stackNeedsAccount,
            status: status
        )
        accountCheckedSinceBuild = decision.decided
        // Cleared before the rebuild awaits, so a second check arriving
        // meanwhile (the account-change loop and Check Again together)
        // doesn't rebuild again and pull the stores from under the first.
        stackNeedsAccount = decision.needsAccount
        if decision.rebuild { await rebuildStack(because: "iCloud account arrived after launch") }
    }
}

// MARK: - Sample class

extension AssistantBootstrapper {
    /// The join screen's Try a Sample Class: a made-up class kept on this
    /// iPhone for the day, so its marks are still there when she comes back.
    /// The real stack stays open underneath (Siri and joining still use it);
    /// only the screens switch.
    func openSampleClass() {
        guard case .needsClassroom = phase else { return }
        do {
            let sample = try AssistantSampleClass.savedStack()
            AssistantSampleClass.isChosen = true
            AssistantSampleClass.wasOpen = true
            coreDataStack = sample
            phase = .ready
            settleDeferredStop()
        } catch {
            Self.logger.error("Sample class failed: \(error.localizedDescription, privacy: .public)")
            ToastService.shared.showError("Couldn't open the sample class. Try again, or restart the app.")
        }
    }

    /// Back into the sample after a relaunch or a rebuild if it was open,
    /// unless a classroom arrived meanwhile: the real class wins then.
    private func resumeSample() async {
        guard AssistantSampleClass.wasOpen else { return }
        if case .needsClassroom = phase {
            openSampleClass()
        } else {
            AssistantSampleClass.wasOpen = false
            await EarlyPickupReminder.cancelSample()
        }
    }

    /// Back from the sample class to the real stack, and to joining unless a
    /// classroom arrived meanwhile.
    func leaveSampleClass() {
        guard AssistantSampleClass.isChosen else { return }
        AssistantSampleClass.isChosen = false
        AssistantSampleClass.wasOpen = false
        Task { await EarlyPickupReminder.cancelSample() }
        coreDataStack = AssistantStack.isOpen ? try? AssistantStack.shared() : nil
        refreshMembership()
        if coreDataStack == nil { phase = .needsClassroom }
        // A name set in the sample went nowhere: it goes into the class's list.
        writeWaitingName()
    }
}
