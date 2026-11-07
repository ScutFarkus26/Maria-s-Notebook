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
    var accountStatus: CKAccountStatus?

    @ObservationIgnored var acceptanceObserver: (any NSObjectProtocol)?
    @ObservationIgnored var invitationObserver: (any NSObjectProtocol)?
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
    var stackNeedsAccount = false
    /// Whether the account has been checked since the stack was built.
    var accountCheckedSinceBuild = false
    /// Set while this iPhone's own Leave runs (`+Leave`). Its membership
    /// delete comes back as a remote change, which `followLeaveElsewhere`
    /// read as a Leave on another device.
    var isLeavingHere = false
    /// A rebuild was called for while her Leave ran (the account arrived,
    /// the class store's setup failed for it): none runs under a Leave, so
    /// the account is checked again when it ends (bug hunt 2026-11-06 #8).
    @ObservationIgnored var accountCheckAfterLeave = false
    /// Set while `start()` runs: launch and the window both start it.
    private var isStarting = false
    /// A start has run to its end at least once.
    @ObservationIgnored private var startedOnce = false
    /// The first unlock came while a start ran or was still to come
    /// (`retryFailedStart`): tried when that start ends, if it failed.
    @ObservationIgnored private var retriesWhenStartEnds = false
    /// Set while `rebuildStack` runs: one rebuild at a time, and a mirroring
    /// stop meanwhile waits (`mirroringStopped(in:)`), as it did while every
    /// rebuild showed "Starting…".
    @ObservationIgnored private(set) var isRebuilding = false
    /// The invitation a rebuild accepted again after its join failed on the
    /// old stack (`waitForJoinBeforeRebuild`): only once.
    @ObservationIgnored var rejoinedInvitation: CKRecord.ID?
    /// After "Download from iCloud again" on a phone that was in a class:
    /// "Starting…" stays up until the membership comes back down, rather
    /// than the join screen (`refreshMembership`), for at most
    /// `membershipWaitLimit`.
    @ObservationIgnored var awaitsMembership = false
    /// Where Leave takes this class's reminders off (`backToJoining`): the
    /// system's, or a stand-in in the tests, where the simulator's own
    /// center took up to a minute to answer.
    @ObservationIgnored var reminderCenter: any ReminderCenter = SystemReminderCenter()
    @ObservationIgnored var membershipWait: Task<Void, Never>?
    /// When the stack was last rebuilt because the class store's iCloud
    /// setup failed for want of an account, with the account there now
    /// (`rebuildIfSetupFailed`): a second such failure soon after gives up.
    @ObservationIgnored var rebuiltForFailedSetupAt: Date?
    /// How many times the class became ready here, its becoming-ready steps
    /// run (`refreshMembership`). The tests read it.
    @ObservationIgnored private(set) var timesBecameReady = 0
    /// Asks about the account again while it's unknown (`retryUnknownAccount`).
    @ObservationIgnored var accountRetry: Task<Void, Never>?
    @ObservationIgnored let accountRetryDelay: Duration

    /// Asks CloudKit for the account's status; tests pass their own.
    @ObservationIgnored let fetchAccountStatus: @MainActor () async throws -> CKAccountStatus
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
    @ObservationIgnored var accountCheck = 0
    /// Mirroring stopped again after its one rebuild (`mirroringStopped(in:)`).
    var sendingStopped = false
    /// When the stack was last rebuilt because mirroring stopped: a second
    /// stop soon after gives up rather than rebuilding round and round, but
    /// one hours later, on a stack that worked meanwhile, gets its rebuild.
    @ObservationIgnored var rebuiltForMirroringStopAt: Date?
    /// When the stack was last rebuilt because sending stalled on a usable
    /// network (`sendStalled`): the next stall within `stallRebuildWindow`
    /// is left to the attacher's own rests.
    @ObservationIgnored var rebuiltForStallAt: Date?
    /// The attacher's count of rounds that put marks in (`sendsSoFar`) at
    /// the last rebuild for a stall: another rebuild for one waits until a
    /// send has worked since (bug hunt 2026-11-02 #42). Nil before the first.
    @ObservationIgnored var sendsAtStallRebuild: Int?
    /// The container a mirroring stop has already rebuilt: the filing hold
    /// and the attacher can both report the same stop, and the second report
    /// read as the rebuilt stack stopping too (#5).
    @ObservationIgnored weak var stopRebuiltContainer: NSPersistentCloudKitContainer?
    /// Taken out of the class (`checkStillInClass`).
    var removedFromClass = false
    @ObservationIgnored var classCheck: Task<Void, Never>?
    @ObservationIgnored var classCheckAgain = false
    /// The history trim's export recorder, and whether this launch trimmed.
    @ObservationIgnored var exportRecorder: Task<Void, Never>?
    @ObservationIgnored var historyTrimmed = false
    /// The class's ParentLocker sync, on the real stack only
    /// (`startParentLocker`); the screens read it through `parentLockerForScreens`.
    var parentLocker: ParentLockerSync?
    /// Where rebuilt stacks, the Sample Class and the filing hold come from;
    /// tests pass their own (`Stacks`).
    @ObservationIgnored let stacks: Stacks
    @ObservationIgnored let now: @MainActor () -> Date
    /// Whether a sheet is up (the Mail composer, the Classroom screen, a
    /// sign-in): a rebuild for a stall waits rather than take it down (#42).
    @ObservationIgnored let sheetIsUp: @MainActor () -> Bool
    /// The attacher's `sendsSoFar`; tests pass their own.
    @ObservationIgnored let sendsSoFar: @MainActor () -> Int

    init(
        fetchAccountStatus: @escaping @MainActor () async throws -> CKAccountStatus = {
            try await CloudKitConfigurationService.container.accountStatus()
        },
        fetchUserRecordName: @escaping @MainActor () async throws -> String = {
            try await CloudKitConfigurationService.container.userRecordID().recordName
        },
        accountRetryDelay: Duration = .seconds(10),
        stacks: Stacks = .live,
        now: @escaping @MainActor () -> Date = Date.init,
        sheetIsUp: @escaping @MainActor () -> Bool = { AssistantBootstrapper.anySheetIsUp() },
        sendsSoFar: @escaping @MainActor () -> Int = { AssistantShareAttacher.shared.sendsSoFar }
    ) {
        self.fetchAccountStatus = fetchAccountStatus
        self.fetchUserRecordName = fetchUserRecordName
        self.accountRetryDelay = accountRetryDelay
        self.stacks = stacks
        self.now = now
        self.sheetIsUp = sheetIsUp
        self.sendsSoFar = sendsSoFar
    }

    func start() async {
        // Once: not again over a stack that's open (waiting for its
        // membership after a download) or being rebuilt.
        guard case .starting = phase, !isStarting, coreDataStack == nil, !isRebuilding else { return }
        isStarting = true
        startOnce()
        isStarting = false
        startedOnce = true
        // The first unlock came while this start ran, or before it: its
        // retry was waiting for this one to end (bug hunt 2026-11-06 #10).
        if retriesWhenStartEnds {
            retriesWhenStartEnds = false
            await retryFailedStart()
        }
    }

    private func startOnce() {
        // A "Download from iCloud again" still waiting for its membership:
        // after a relaunch too, "Starting…" waits for it, not the join screen.
        if AssistantClassroomLocalState.awaitsMembership() { awaitsMembership = true }

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
        // its pickup reminders. Otherwise they outlive it, and come off, not
        // waited for, as `resumeSample` and `leaveSampleClass` do: the store
        // used to open only after the notification center answered, and a
        // background push gets only seconds (hunt 2026-11-03 #14).
        let reopenSample = AssistantSampleClass.wasOpen
        if !reopenSample { Task { await EarlyPickupReminder.cancelSample() } }

        do {
            // Shared with Siri, which may have opened it already.
            install(try stacks.open())
            restoreName()
            observeAcceptance()
            observeRemoteChanges()
            observeAccountChanges()
            observeReturnToForeground()
            observeMirroringStops()
            startHistoryUpkeep()
            if reopenSample { resumeSample() }
        } catch {
            Self.logger.error("Assistant bootstrap failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(AssistantStartupProblem(error, storesOpen: stacks.isOpen()))
        }
    }

    /// A start that failed with no store open, tried again: after the first
    /// unlock following a restart (`AssistantApp`), when a background
    /// relaunch before it couldn't read the class's files, and "Can't start"
    /// used to stay until the app was killed (hunt 2026-11-03 #35).
    ///
    /// An unlock that came while a start ran, or before the first one did,
    /// used to find nothing failed yet and end the listener: "Can't start"
    /// then stayed until the app was killed (bug hunt 2026-11-06 #10). Now
    /// that retry waits for the start, and runs if it fails.
    func retryFailedStart() async {
        guard coreDataStack == nil, !stacks.isOpen(), !isRebuilding else { return }
        if isStarting || startIsDue {
            retriesWhenStartEnds = true
            return
        }
        guard case .failed = phase else { return }
        phase = .starting
        await start()
    }

    /// No start has ended yet: launch's and the window's are still to come.
    private var startIsDue: Bool {
        if case .starting = phase, !startedOnce { true } else { false }
    }

    /// Takes a newly built stack: its sharing service, and the phase its
    /// membership row gives.
    private func install(_ stack: CoreDataStack) {
        let sampleWasChosen = AssistantSampleClass.isChosen
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
        // The sample's `.ready` isn't the class's: read as it, a class that arrived
        // underneath skipped becoming ready (2026-10-20 review b, item 5).
        if sampleWasChosen { phase = .needsClassroom }

        refreshMembership()
        followFailedSetup(on: stack)
        // A test's stack is in memory: no ParentLocker sync (one per app,
        // `ParentLockerSync.current`), and nothing asked of iCloud.
        guard stacks.isLive else { return }
        startParentLocker(on: stack)
        // Where each name row lives, for the screens' reads: a new stack has
        // new stores and new object IDs. Asked of CloudKit off the main thread.
        let viewContext = stack.viewContext
        Task { await ClassroomNames.warmZones(in: viewContext) }
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
    /// (`mirroringStopped(in:)`). A running attach finishes on the old one
    /// first (`waitForAttachBeforeRebuild`), and the screens let go of it
    /// (`screensLetGo`), so nothing reads its objects once its stores are gone.
    ///
    /// A join running on the old stack finishes first, up to its own limit:
    /// a rebuild under it lost the join (bug hunt 2026-10-20 #8). If it
    /// failed, or still runs then, it's accepted again on the new stack, once.
    /// "Starting…" shows only on a phone that has joined (`rebuildShowsStarting`):
    /// the join screen, or the Sample Class, stays up meanwhile, so setup
    /// keeps its page (#22).
    ///
    /// The screens stay up through those waits, up to half a minute: they
    /// came down at once, so every rebuild flashed "Starting…" and took any
    /// sheet down with it (bug hunt 2026-11-02 #42). They come down only for
    /// the swap itself. `abandon`, asked once the waits are over, drops a
    /// rebuild that should no longer happen (a sheet came up meanwhile); it
    /// returns false then, and true otherwise, a rebuild already running
    /// included.
    @discardableResult
    func rebuildStack(because reason: String, unless abandon: (@MainActor () -> Bool)? = nil) async -> Bool {
        guard !isRebuilding else {
            Self.logger.info("\(reason, privacy: .public); a rebuild is already running")
            return true
        }
        // Never under her Leave, which reads the stack and its sharing
        // service throughout: Leave failed partway and left a half-purged
        // class (bug hunt 2026-11-06 #8). Each caller holds back while she
        // leaves; this is the backstop, and asks again once she has.
        guard !isLeavingHere else {
            Self.logger.notice("\(reason, privacy: .public); waits for Leave to end")
            accountCheckAfterLeave = true
            return false
        }
        let rebuilt = await rebuildOnce(because: reason, unless: abandon)
        // A stop heard while this ran waited for it to end.
        settleDeferredStop()
        guard rebuilt else { return false }
        // The new stack's setup may have failed for the account at once,
        // while this ran: heard then, it waited for now (`rebuildIfSetupFailed`).
        await rebuildIfSetupFailed()
        return true
    }

    private func rebuildOnce(because reason: String, unless abandon: (@MainActor () -> Bool)?) async -> Bool {
        isRebuilding = true
        defer { isRebuilding = false }
        Self.logger.info("\(reason, privacy: .public); rebuilding the Core Data stack")
        var failedJoin = await waitForJoinBeforeRebuild(on: sharingService)
        let attacher = AssistantShareAttacher.shared
        attacher.hold()
        defer { attacher.release() }
        await waitForAttachBeforeRebuild(attacher)
        // The join screen stayed up through that wait: a join started on it
        // meanwhile finishes too.
        if failedJoin == nil { failedJoin = await waitForJoinBeforeRebuild(on: sharingService) }
        // A ParentLocker send under way finishes first, before the rebuild
        // asks whether it's still wanted: a sheet she opened during that
        // wait counts (bug hunt 2026-11-06 #9). Nothing awaits between the
        // question and the stop below, so no new send starts in between.
        await waitForParentLockerBeforeRebuild()
        if failedJoin == nil, abandon?() == true {
            Self.logger.notice("The rebuild isn't needed now; the stack stays as it is")
            // Left the Sample Class meanwhile, expecting the new stack
            // (`leaveSampleClass`): back to the open one.
            if coreDataStack == nil, !AssistantSampleClass.isChosen, let open = stacks.current() {
                coreDataStack = open
                refreshMembership()
                writeWaitingName()
            }
            return false
        }
        stopParentLockerBeforeRebuild()
        let joined = if case .ready = phase { true } else { false }
        let inSample = AssistantSampleClass.isChosen
        if Self.rebuildShowsStarting(ready: joined, starting: isStartingPhase, inSample: inSample) {
            phase = .starting
            coreDataStack = nil
        } else if !inSample {
            // The join screen reads no stack; the sample keeps its own.
            coreDataStack = nil
        }
        sharingService = nil
        await letScreensGo()
        // The new stack's service takes it when it's built.
        if let failedJoin { ShareInvitationInbox.keep(failedJoin) }
        do {
            install(try stacks.rebuild())
            resumeSample()
        } catch {
            Self.logger.error("Assistant rebuild failed: \(error.localizedDescription, privacy: .public)")
            coreDataStack = nil
            phase = .failed(AssistantStartupProblem(error, storesOpen: AssistantStack.isOpen))
        }
        return true
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
            // Read before it's forgotten: a phone that was in a class waits on
            // "Starting…" for its membership, not the join screen. Kept until it's
            // back: a second download found the key gone (2026-10-20 review b, item 9).
            awaitsMembership = awaitsMembership || AssistantClassroomLocalState.wasInAClass()
            CoreDataStack.performLocalCacheReset()
            AssistantClassroomLocalState.forget()
            if awaitsMembership { AssistantClassroomLocalState.noteAwaitsMembership() }
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
        let read: Phase = hasMembership ? .ready : awaitsMembership ? .starting : .needsClassroom
        // Set only when it changes: every set redraws the screens that read it.
        let unchanged = switch (phase, read) {
        case (.ready, .ready), (.starting, .starting), (.needsClassroom, .needsClassroom): true
        default: false
        }
        if !unchanged { phase = read }
        noteMembershipRead(hasMembership: hasMembership)
        // Marks an earlier Leave couldn't sort go before anything new is filed.
        Task { await deleteLeftBehindMarks() }
        guard let service = sharingService else { return }
        service.loadCurrentMembership()
        guard hasMembership, !wasReady else { return }
        timesBecameReady += 1
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
            let sample = try stacks.sample()
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
    /// unless a classroom arrived meanwhile: the real class wins then. Its
    /// reminders come off as leaving it takes them off, not waited for: a
    /// rebuild held up behind the reminders' queue held every later one up.
    func resumeSample() {
        guard AssistantSampleClass.wasOpen else { return }
        let needsClassroom = if case .needsClassroom = phase { true } else { false }
        if Self.reopensSample(needsClassroom: needsClassroom, joining: sharingService?.isJoining ?? false) {
            openSampleClass()
        } else {
            AssistantSampleClass.wasOpen = false
            Task { await EarlyPickupReminder.cancelSample() }
        }
    }

    /// Back from the sample class to the real stack, and to joining unless a
    /// classroom arrived meanwhile.
    func leaveSampleClass() {
        guard AssistantSampleClass.isChosen else { return }
        AssistantSampleClass.isChosen = false
        AssistantSampleClass.wasOpen = false
        Task { await EarlyPickupReminder.cancelSample() }
        guard !isRebuilding else {
            // The stack underneath is about to come off, under any screens
            // opened on it: `install` opens the new one (2026-10-20 review b, item 5).
            coreDataStack = nil
            phase = .needsClassroom
            return
        }
        coreDataStack = stacks.current()
        // The sample's `.ready` isn't the class's: a class that arrived
        // underneath gets the steps of becoming ready (its guide's name, the
        // retry of waiting marks, the removed check), which a read that took
        // the sample for the class skipped (bug hunt 2026-10-20 #13).
        phase = .needsClassroom
        refreshMembership()
        // A name set in the sample went nowhere: it goes into the class's list.
        writeWaitingName()
    }
}
