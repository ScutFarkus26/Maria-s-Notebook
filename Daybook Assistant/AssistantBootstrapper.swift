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
            let stack = try AssistantStack.shared()
            coreDataStack = stack

            let service = ClassroomSharingService(
                container: stack.container,
                context: stack.viewContext
            )
            sharingService = service

            restoreName()
            observeAcceptance()
            observeAccountChanges()
            refreshMembership()
            if case .ready = phase {
                // Only joining fills in the share otherwise: the guide's name
                // on the Classroom screen, and "you" on her own marks.
                Task { await service.refreshShareInBackground() }
            }
        } catch {
            Self.logger.error("Assistant bootstrap failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Re-reads the membership row. Acceptance writes one, and the roster only
    /// starts arriving afterwards, so this is what flips onboarding to the
    /// attendance list.
    func refreshMembership() {
        guard let context = coreDataStack?.viewContext else { return }
        let request = CDClassroomMembership.ownRowsRequest()
        request.fetchLimit = 1
        let hasMembership = context.safeFetchFirst(request) != nil
        phase = hasMembership ? .ready : .needsClassroom
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
