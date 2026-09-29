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

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DaybookAssistant",
        category: "bootstrap"
    )

    enum Phase {
        case starting
        case needsClassroom
        case ready
        case failed(String)
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

        #if DEBUG
        if AssistantSampleClass.isRequested {
            do {
                coreDataStack = try AssistantStack.shared()
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
            return
        }
        #endif

        do {
            // Shared with Siri, which may have opened it already.
            install(try AssistantStack.shared())
            restoreName()
            observeAcceptance()
            observeRemoteChanges()
            observeAccountChanges()
        } catch {
            Self.logger.error("Assistant bootstrap failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Takes a newly built stack: its sharing service, and the phase its
    /// membership row gives.
    private func install(_ stack: CoreDataStack) {
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
            phase = .failed(error.localizedDescription)
        }
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
        if hasMembership, !wasReady, service.currentShare == nil {
            // Only joining fills in the share otherwise: the guide's name
            // on the Classroom screen, and "you" on her own marks.
            Task { await service.refreshShareInBackground() }
        }
    }

    /// Leaves the classroom: the class comes off this iPhone and the screen
    /// goes back to joining. Her marks stay with the guide.
    func leaveClassroom() async throws {
        try await sharingService?.leaveClassroom()
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
        guard coreDataStack != nil else { return }
        if !accountCheckedSinceBuild {
            accountCheckedSinceBuild = true
            stackNeedsAccount = accountStatus != .available
        } else if stackNeedsAccount, accountStatus == .available {
            await rebuildStackForAccount()
        }
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
            MainActor.assumeIsolated { self?.refreshMembership() }
        }
    }
}
