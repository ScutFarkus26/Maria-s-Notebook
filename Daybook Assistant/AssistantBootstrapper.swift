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

    private var acceptanceObserver: (any NSObjectProtocol)?
    private var accountObserver: Task<Void, Never>?
    private var nameObserver: (any NSObjectProtocol)?
    private var remoteChangeObserver: Task<Void, Never>?
    /// Set when the first account check after building the stack found no
    /// usable iCloud account. `NSPersistentCloudKitContainer` fails its setup
    /// then, and although it later imports once the account appears, sharing
    /// stays broken for the life of the container: every new mark fails to
    /// attach to the classroom and sits at "Not sent yet" until the app is
    /// relaunched. So the stack is rebuilt when the account arrives.
    private var stackNeedsAccount = false
    /// Whether the account has been checked since the stack was built.
    private var accountCheckedSinceBuild = false

    /// True inside a hosted `Daybook Assistant Tests` run, the same check as
    /// the notebook's `AppBootstrapping.isRunningUnitTests`.
    nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func start() async {
        guard case .starting = phase else { return }

        if AssistantSampleClass.isRequested {
            do {
                coreDataStack = try AssistantStack.shared()
                phase = .ready
            } catch {
                phase = .failed(AssistantStartupProblem(error, storesOpen: AssistantStack.isOpen))
            }
            return
        }

        do {
            // Shared with Siri, which may have opened it already.
            install(try AssistantStack.shared())
            restoreName()
            observeAcceptance()
            observeRemoteChanges()
            observeAccountChanges()
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

        refreshMembership()
    }

    /// Builds the stack again now that iCloud is signed in (see
    /// `stackNeedsAccount`). The screens let go of the old one first, so
    /// nothing reads its objects once its stores are gone.
    private func rebuildStackForAccount() async {
        Self.logger.info("iCloud account arrived after launch; rebuilding the Core Data stack")
        phase = .starting
        sharingService = nil
        coreDataStack = nil
        try? await Task.sleep(for: .milliseconds(300))
        do {
            install(try AssistantStack.rebuild())
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
    func rebuildFromICloud() async {
        guard case .failed(let problem) = phase, problem.canRebuild, !AssistantStack.isOpen else { return }
        Self.logger.warning("Rebuilding the class from iCloud after a failed start")
        phase = .starting
        CoreDataStack.performLocalCacheReset()
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
        let request = CDClassroomMembership.ownRowsRequest()
        request.fetchLimit = 1
        let hasMembership = context.safeFetchFirst(request) != nil
        let wasReady = if case .ready = phase { true } else { false }
        phase = hasMembership ? .ready : .needsClassroom
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
    }

    /// The join screen's Try a Sample Class: a made-up class in memory for
    /// this session. The real stack stays open underneath (Siri and joining
    /// still use it); only the screens switch.
    func openSampleClass() {
        guard case .needsClassroom = phase else { return }
        do {
            let sample = try AssistantSampleClass.makeStack()
            AssistantSampleClass.isChosen = true
            coreDataStack = sample
            phase = .ready
        } catch {
            Self.logger.error("Sample class failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Back from the sample class to the real stack, and to joining unless a
    /// classroom arrived meanwhile.
    func leaveSampleClass() {
        guard AssistantSampleClass.isChosen else { return }
        AssistantSampleClass.isChosen = false
        coreDataStack = AssistantStack.isOpen ? try? AssistantStack.shared() : nil
        refreshMembership()
        if coreDataStack == nil { phase = .needsClassroom }
    }

    /// Leaves the classroom: the class comes off this iPhone and the screen
    /// goes back to joining. Her marks stay with the guide.
    func leaveClassroom() async throws {
        try await sharingService?.leaveClassroom()
        await ArrivalReminder.cancelAll()
        await FrontDeskEmailReminder.cancelAll()
        refreshMembership()
    }

    /// The guide's name as the share's owner identity gives it, for display
    /// only (Apple's terms: never stored). Nil when CloudKit withholds it.
    var guideName: String? {
        let name = sharingService?.currentShare?.owner.userIdentity.nameComponents?.formatted().trimmed() ?? ""
        return name.isEmpty ? nil : name
    }

    func refreshAccountStatus() async {
        do {
            accountStatus = try await CloudKitConfigurationService.container.accountStatus()
        } catch {
            // Unknown isn't a problem worth showing; keep what we had.
            Self.logger.error("iCloud account status failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard coreDataStack != nil, let accountStatus else { return }
        let decision = Self.accountDecision(
            checkedSinceBuild: accountCheckedSinceBuild,
            needsAccount: stackNeedsAccount,
            status: accountStatus
        )
        accountCheckedSinceBuild = true
        // Cleared before the rebuild awaits, so a second check arriving
        // meanwhile (the account-change loop and Check Again together)
        // doesn't rebuild again and pull the stores from under the first.
        stackNeedsAccount = decision.needsAccount
        if decision.rebuild { await rebuildStackForAccount() }
    }

    /// What one account check means for the stack. The first check after a
    /// build decides whether it came up without an account; after that, the
    /// account arriving is the one reason to rebuild, once.
    nonisolated static func accountDecision(
        checkedSinceBuild: Bool,
        needsAccount: Bool,
        status: CKAccountStatus
    ) -> (needsAccount: Bool, rebuild: Bool) {
        guard checkedSinceBuild else { return (status != .available, false) }
        if needsAccount, status == .available { return (false, true) }
        return (needsAccount, false)
    }

    /// Asks now, and again whenever the account changes (signed out in
    /// Settings, say), for as long as the app runs.
    private func observeAccountChanges() {
        guard accountObserver == nil else { return }
        accountObserver = Task { [weak self] in
            await self?.refreshAccountStatus()
            let changes = NotificationCenter.default.notifications(named: .CKAccountChanged).map { _ in () }
            for await _ in changes {
                await self?.refreshAccountStatus()
            }
        }
    }

    /// Her name from iCloud on a new iPhone, now or when key-value storage
    /// catches up, so the first-run name sheet isn't needed.
    private func restoreName() {
        AssistantNameStore.restoreIfNeeded()
        guard nameObserver == nil else { return }
        nameObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { _ = AssistantNameStore.restoreIfNeeded() }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// A membership row can also arrive by sync rather than by accepting a
    /// link here: on a new iPhone, or after signing in, for an Apple Account
    /// that joined before. Nothing posts `.didJoinClassroom` then, so until
    /// this device has a classroom every import re-reads the row.
    private func observeRemoteChanges() {
        guard remoteChangeObserver == nil else { return }
        remoteChangeObserver = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: .NSPersistentStoreRemoteChange)
                .map { _ in () }
            for await _ in changes {
                guard let self else { return }
                if case .needsClassroom = phase { refreshMembership() }
            }
        }
    }

    /// ClassroomSharingService does the accepting and posts once the
    /// membership row is written, however long CloudKit took.
    private func observeAcceptance() {
        guard acceptanceObserver == nil else { return }
        acceptanceObserver = NotificationCenter.default.addObserver(
            forName: .didJoinClassroom,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Joined while looking at the sample: the real class wins.
                self?.leaveSampleClass()
                self?.refreshMembership()
            }
        }
    }
}
