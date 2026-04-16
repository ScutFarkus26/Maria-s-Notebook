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

    // MARK: - Observable State

    private(set) var currentRole: CDClassroomMembership.ClassroomRole = .leadGuide
    private(set) var participants: [CKShare.Participant] = []
    private(set) var isSharing: Bool = false
    private(set) var shareError: String?
    private(set) var currentShare: CKShare?

    // MARK: - Initialization

    init(container: NSPersistentCloudKitContainer, context: NSManagedObjectContext) {
        self.container = container
        self.context = context

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShareAcceptance(_:)),
            name: .didAcceptCloudKitShare,
            object: nil
        )

        loadCurrentMembership()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Share Lifecycle

    /// Fetches the existing CKShare for the shared store, if any.
    func fetchExistingShare() throws -> CKShare? {
        guard let store = sharedStore else { return nil }
        let shares = try container.fetchShares(in: store)
        let share = shares.first
        currentShare = share
        isSharing = share != nil
        return share
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
