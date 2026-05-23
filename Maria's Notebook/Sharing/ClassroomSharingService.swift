import Foundation
import CoreData
import CloudKit
import OSLog

/// Manages CloudKit classroom sharing lifecycle.
///
/// Wraps NSPersistentCloudKitContainer zone-based sharing APIs to
/// create, accept, manage, and leave shared classrooms.
@Observable
@MainActor
final class ClassroomSharingService {
    private static let logger = Logger.app(category: "ClassroomSharing")

    let container: NSPersistentCloudKitContainer
    private let context: NSManagedObjectContext
    private let coreDataStack: CoreDataStack?

    // MARK: - Observable State

    private(set) var currentRole: CDClassroomMembership.ClassroomRole = .leadGuide
    private(set) var participants: [CKShare.Participant] = []
    private(set) var isSharing: Bool = false
    private(set) var shareError: String?
    private(set) var currentShare: CKShare?

    // `@ObservationIgnored nonisolated(unsafe)` so deinit (which is
    // nonisolated by default on MainActor classes) can release the observer
    // token without crossing actor isolation. Mutation is confined to init.
    @ObservationIgnored nonisolated(unsafe) private var remoteChangeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var participantRefreshTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        container: NSPersistentCloudKitContainer,
        context: NSManagedObjectContext,
        coreDataStack: CoreDataStack? = nil
    ) {
        self.container = container
        self.context = context
        self.coreDataStack = coreDataStack

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShareAcceptance(_:)),
            name: .didAcceptCloudKitShare,
            object: nil
        )

        // Refresh participants when CloudKit delivers a remote change to the
        // coordinator. Without this, a participant joining via their accept
        // link wouldn't flip from "Invited" to "Joined" in the UI until the
        // user manually reopens Settings → Classroom Sharing.
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleParticipantRefresh()
            }
        }

        loadCurrentMembership()
    }

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Internal State Setters

    /// Updates observable share state directly. Used by the +AutoCreate
    /// extension after `container.share(_:to:)` succeeds so we don't have to
    /// round-trip through a re-fetch (which can throw and leave `currentShare`
    /// nil even though the share was actually created — causing the sharing
    /// sheet to present empty).
    func updateShareState(_ share: CKShare?) {
        let wasSharing = isSharing
        currentShare = share
        isSharing = share != nil

        if !wasSharing, isSharing, let stack = coreDataStack {
            Task { await SharedStoreZoneRepair.runIfNeeded(coreDataStack: stack) }
        }
    }

    // MARK: - Share Lifecycle

    /// Fetches the existing CKShare for this device's classroom, if any.
    ///
    /// Role-aware lookup: the share's location depends on the user's role.
    /// - **Lead guide**: their own share lives in the `.private`-scope private
    ///   store (the canonical sharing pattern requires owner-side shareable
    ///   data + the CKShare to live in the user's private CloudKit database).
    /// - **Assistant**: an accepted share lives in the `.shared`-scope shared
    ///   store, which is exactly what `container.acceptShareInvitations(into:)`
    ///   targets.
    ///
    /// Avoiding the iterate-all-stores approach prevents legacy shares left
    /// in the wrong store (from the pre-migration era) from being surfaced
    /// to the UI.
    ///
    /// When `isSharing` transitions from `false → true` (e.g. the lead guide
    /// just finished the sharing flow), this also kicks off a
    /// `SharedStoreZoneRepair.runIfNeeded` pass so any records that were
    /// created before the share existed get attached to the new zone. We use
    /// `runIfNeeded` (not `run`) so the circuit breaker can block the call
    /// when CloudKit is unhealthy.
    func fetchExistingShare() throws -> CKShare? {
        let stores = container.persistentStoreCoordinator.persistentStores
        let preferredConfig: String
        switch currentRole {
        case .leadGuide:
            preferredConfig = CoreDataStack.privateConfiguration
        case .assistant:
            preferredConfig = CoreDataStack.sharedConfiguration
        }
        let preferredStore = stores.first { $0.configurationName == preferredConfig }

        var found: CKShare?
        if let store = preferredStore {
            found = try container.fetchShares(in: store).first
        }

        let wasSharing = isSharing
        currentShare = found
        isSharing = found != nil

        if !wasSharing, isSharing, let stack = coreDataStack {
            Task { await SharedStoreZoneRepair.runIfNeeded(coreDataStack: stack) }
        }

        return found
    }

    /// Refreshes participant list from the current CKShare.
    func refreshParticipants() throws {
        let share = try fetchExistingShare()
        participants = share?.participants.map { $0 } ?? []
    }

    /// Accepts an incoming share invitation.
    /// Called via notification when user taps a share link.
    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let store = sharedStore else {
            Self.logger.error("Cannot accept share: shared store not found")
            shareError = "Shared store not available"
            ToastService.shared.showError("Unable to join classroom — shared storage not available")
            return
        }

        Self.logger.info("Accepting CloudKit share invitation...")
        try await container.acceptShareInvitations(from: [metadata], into: store)

        // Create local membership record as assistant
        let repo = ClassroomRepository(context: context)
        repo.createMembership(
            classroomZoneID: metadata.share.recordID.zoneID.zoneName,
            role: .assistant,
            ownerIdentity: metadata.ownerIdentity.userRecordID?.recordName ?? "unknown"
        )
        _ = repo.save(reason: "Accept classroom share")

        loadCurrentMembership()
        try refreshParticipants()
        Self.logger.info("Share accepted successfully")
    }

    /// Leaves the current shared classroom (assistant only).
    /// Purges local shared data and removes the membership record.
    func leaveClassroom() async throws {
        guard currentRole == .assistant else {
            Self.logger.warning("Only assistants can leave a classroom")
            return
        }

        if let store = sharedStore, let share = currentShare {
            let zoneID = share.recordID.zoneID
            Self.logger.info("Purging shared zone: \(zoneID.zoneName)")
            try await container.purgeObjectsAndRecordsInZone(with: zoneID, in: store)
        }

        // Remove local membership
        let repo = ClassroomRepository(context: context)
        if let membership = repo.fetchCurrentMembership() {
            repo.deleteMembership(id: membership.id!)
            _ = repo.save(reason: "Leave classroom")
        }

        currentShare = nil
        participants = []
        isSharing = false
        currentRole = .leadGuide
        Self.logger.info("Left classroom successfully")
    }

    // MARK: - Permission Queries

    func canWrite(entityName: String) -> Bool {
        ClassroomPermissions.canWrite(entityName: entityName, role: currentRole)
    }

    func canManageSharing() -> Bool {
        ClassroomPermissions.canManageSharing(role: currentRole)
    }

    // MARK: - Private

    private var sharedStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            store.configurationName == CoreDataStack.sharedConfiguration
        }
    }

    private func loadCurrentMembership() {
        let repo = ClassroomRepository(context: context)
        if let membership = repo.fetchCurrentMembership() {
            currentRole = membership.role
        } else {
            currentRole = .leadGuide
        }
    }

    /// Debounces a participant refresh so a burst of remote-change
    /// notifications collapses into one refetch.
    private func scheduleParticipantRefresh() {
        participantRefreshTask?.cancel()
        participantRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard let self else { return }
            try? self.refreshParticipants()
        }
    }

    @objc private func handleShareAcceptance(_ notification: Notification) {
        guard let metadata = notification.object as? CKShare.Metadata else { return }
        Task { @MainActor in
            do {
                try await acceptShare(metadata: metadata)
            } catch {
                Self.logger.error("Share acceptance failed: \(error.localizedDescription)")
                let message = AppErrorMessages.userMessage(for: error, context: "joining the classroom")
                shareError = message
                ToastService.shared.showError(message)
            }
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let didAcceptCloudKitShare = Notification.Name("didAcceptCloudKitShare")
}
