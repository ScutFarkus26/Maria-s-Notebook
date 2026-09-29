import Foundation
import CoreData
import CloudKit
import OSLog

/// Manages CloudKit classroom sharing lifecycle.
///
/// Wraps NSPersistentCloudKitContainer zone-based sharing APIs to
/// create, accept, manage, and leave shared classrooms.
@Observable
final class ClassroomSharingService {
    private static let logger = Logger.classroomSharing

    let container: NSPersistentCloudKitContainer
    private let context: NSManagedObjectContext

    // MARK: - Observable State

    private(set) var currentRole: CDClassroomMembership.ClassroomRole = .leadGuide
    private(set) var participants: [CKShare.Participant] = []
    private(set) var isSharing: Bool = false
    private(set) var shareError: String?
    private(set) var currentShare: CKShare?
    /// True while an opened invitation is being joined, which can take a
    /// while; the Daybook Assistant shows "Joining your classroom…".
    private(set) var isJoining = false

    /// Record name of whoever is using this device, so the members list can
    /// mark its own row. CloudKit withholds your own name components, which
    /// otherwise leaves you as an anonymous entry in your own classroom.
    private(set) var currentUserRecordName: String?

    // `@ObservationIgnored nonisolated(unsafe)` so deinit (which is
    // nonisolated by default on MainActor classes) can cancel the observer
    // task without crossing actor isolation. Written only on the main actor
    // (start/stop below); deinit runs after the last reference is gone.
    @ObservationIgnored nonisolated(unsafe) private var remoteChangeTask: Task<Void, Never>?
    @ObservationIgnored private var participantRefreshTask: Task<Void, Never>?
    /// Screens currently showing the members list (see `startObservingParticipants`).
    @ObservationIgnored private var participantObserverCount = 0

    // MARK: - Initialization

    init(
        container: NSPersistentCloudKitContainer,
        context: NSManagedObjectContext
    ) {
        self.container = container
        self.context = context

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShareAcceptance(_:)),
            name: .didAcceptCloudKitShare,
            object: nil
        )

        loadCurrentMembership()

        // The invitation may have arrived before this service existed.
        acceptPendingInvitation()
    }

    /// Refreshes participants on every CloudKit remote change while a screen
    /// that shows them is open. Without this, a participant joining via their
    /// accept link wouldn't flip from "Invited" to "Joined" in the open
    /// screen. Nothing else reads the participant list, so it stops listening
    /// when the last such screen goes away (`stopObservingParticipants`) —
    /// it used to keep refetching the share for the rest of the session.
    func startObservingParticipants() {
        participantObserverCount += 1
        guard remoteChangeTask == nil else { return }
        let coordinator = container.persistentStoreCoordinator
        remoteChangeTask = Task { [weak self] in
            // The notification arrives on a background queue and is not
            // Sendable — map each one to Void so this main-actor task only
            // ever receives a Sendable value.
            let changes = NotificationCenter.default
                .notifications(named: .NSPersistentStoreRemoteChange, object: coordinator)
                .map { _ in () }
            for await _ in changes {
                self?.scheduleParticipantRefresh()
            }
        }
    }

    /// Balances `startObservingParticipants`.
    func stopObservingParticipants() {
        participantObserverCount = max(0, participantObserverCount - 1)
        guard participantObserverCount == 0 else { return }
        remoteChangeTask?.cancel()
        remoteChangeTask = nil
        participantRefreshTask?.cancel()
        participantRefreshTask = nil
    }

    /// Whether the remote-change listener is running (tests read this).
    var isObservingParticipants: Bool { remoteChangeTask != nil }

    deinit {
        remoteChangeTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Internal State Setters

    /// Updates observable share state directly. Used by Set Up Classroom
    /// Sharing after `container.share(_:to:)` succeeds, so a re-fetch (which
    /// can throw while the new zone settles) can't leave `currentShare` nil.
    func updateShareState(_ share: CKShare?) {
        currentShare = share
        isSharing = share != nil
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
    /// to the UI. Only the pinned share counts: with no pin this is nil.
    func fetchExistingShare() throws -> CKShare? {
        var found: CKShare?
        if let store = classroomShareStore {
            found = CDClassroomMembership.classroomShare(among: try container.fetchShares(in: store), in: context)
        }
        publishShare(found)
        return found
    }

    /// The store this device's classroom share lives in: the private store for
    /// the lead guide who owns it, the shared store for an assistant who
    /// accepted it.
    private var classroomShareStore: NSPersistentStore? {
        let wanted = currentRole == .leadGuide
            ? CoreDataStack.privateConfiguration
            : CoreDataStack.sharedConfiguration
        return container.persistentStoreCoordinator.persistentStores.first { $0.configurationName == wanted }
    }

    private func publishShare(_ found: CKShare?) {
        let wasSharing = isSharing
        currentShare = found
        if isSharing != (found != nil) { isSharing = found != nil }

        // The pinned share just became readable here (a new device's import):
        // anything this device created while waiting for it can go in now.
        // The assistant's device owns no share, so the companion leaves this out.
        #if !ASSISTANT_APP
        if !wasSharing, isSharing {
            SharedStoreOrphanGuard.shared.flushPendingIfPossible()
        }
        #endif
    }

    /// Refreshes participant list from the current CKShare.
    func refreshParticipants() throws {
        publishParticipants(of: try fetchExistingShare())
    }

    /// Reads the pinned share and its participants off the main actor. The
    /// Daybook Assistant calls it at launch: otherwise only joining sets them.
    func refreshShareInBackground() async {
        do {
            try await refreshParticipantsOffMain()
        } catch {
            Self.logger.error("Reading the classroom share failed: \(error.localizedDescription)")
        }
    }

    /// `refreshParticipants` with the share fetch off the main actor. It runs
    /// on every CloudKit remote change while a members screen is open, and
    /// `fetchShares(in:)` is a synchronous read of the store's CloudKit
    /// metadata that would otherwise stall the UI mid-sync.
    private func refreshParticipantsOffMain() async throws {
        guard let storeID = classroomShareStore?.identifier else {
            publishShare(nil)
            publishParticipants(of: nil)
            return
        }
        let shares = try await ClassroomShareAttach.shares(inStoreWithIdentifier: storeID, container: container)
        guard !Task.isCancelled else { return }
        let found = CDClassroomMembership.classroomShare(among: shares, in: context)
        publishShare(found)
        publishParticipants(of: found)
    }

    private func publishParticipants(of share: CKShare?) {
        participants = share?.participants.map { $0 } ?? []
        let recordName = share?.currentUserParticipant?.userIdentity.userRecordID?.recordName
        if currentUserRecordName != recordName { currentUserRecordName = recordName }
        if let currentUserRecordName {
            ClassroomIdentity.currentUserRecordName = currentUserRecordName
        }
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

        // Pin the accepted zone on this device's membership row — updating the
        // row an earlier acceptance wrote rather than adding one per invitation.
        let repo = ClassroomRepository(context: context)
        repo.pinClassroom(
            zoneName: metadata.share.recordID.zoneID.zoneName,
            role: .assistant,
            ownerIdentity: metadata.ownerIdentity.userRecordID?.recordName ?? "unknown"
        )
        _ = repo.save(reason: "Accept classroom share")

        loadCurrentMembership()
        shareError = nil
        // The join is done once the membership row is saved. Reading the
        // participants back is a nicety: failing it used to throw from here,
        // so a good join never posted `.didJoinClassroom` and read as a failure.
        do {
            try refreshParticipants()
        } catch {
            Self.logger.error("Joined, but reading the participants failed: \(error.localizedDescription)")
        }
        Self.logger.info("Share accepted successfully")
        NotificationCenter.default.post(name: .didJoinClassroom, object: nil)
    }

    /// Resynchronizes published share state after the owner ends sharing from
    /// the system sharing UI.
    ///
    /// Since iOS 16.4, `NSPersistentCloudKitContainer` observes the system
    /// sharing UI and updates the share it maintains in the store, so no
    /// store-level cleanup is needed here — but the service's published state
    /// (`currentShare`/`isSharing`/`participants`) would otherwise keep
    /// reporting the dead share until the next `fetchExistingShare` call.
    /// Clearing eagerly also prevents further exports from targeting the
    /// deleted share's zone through stale cached state.
    func handleSharingStopped() {
        Self.logger.info("Sharing stopped from system UI — resynchronizing share state")
        currentShare = nil
        participants = []
        isSharing = false
        // Re-read store truth; if the container hasn't recorded the share
        // deletion yet this may transiently resurface it, and the next
        // remote-change-driven refresh converges.
        _ = try? fetchExistingShare()
    }

    /// Leaves the current shared classroom (assistant only).
    /// Purges local shared data and removes the membership record.
    func leaveClassroom() async throws {
        // Read the row again: on a new iPhone it can arrive by sync after this
        // service was built, and the role cached then would make leaving a
        // silent no-op.
        loadCurrentMembership()
        guard currentRole == .assistant else {
            Self.logger.warning("Only assistants can leave a classroom")
            return
        }

        // After a relaunch nothing has fetched the share yet; without this the
        // purge was skipped and only the membership row went.
        let share = try currentShare ?? fetchExistingShare()
        if let store = sharedStore, let share {
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

    func canManageSharing() -> Bool {
        ClassroomPermissions.canManageSharing(role: currentRole)
    }

    // MARK: - Private

    private var sharedStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            store.configurationName == CoreDataStack.sharedConfiguration
        }
    }

    /// Re-reads the role from the current membership row. The Daybook
    /// Assistant calls it when a row arrives by sync rather than by accepting
    /// an invitation here.
    func loadCurrentMembership() {
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
        participantRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard let self else { return }
            try? await self.refreshParticipantsOffMain()
        }
    }

    @objc private func handleShareAcceptance(_ notification: Notification) {
        acceptPendingInvitation()
    }

    /// Takes the invitation waiting in `ShareInvitationInbox`, if any, and
    /// joins its classroom. A service with no shared store (the Sample Class)
    /// leaves the invitation for the real notebook's service.
    private func acceptPendingInvitation() {
        guard sharedStore != nil, let metadata = ShareInvitationInbox.take() else { return }
        isJoining = true
        shareError = nil
        Task {
            defer { isJoining = false }
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
    /// Posted by `ShareInvitationInbox` when an invitation is waiting.
    static let didAcceptCloudKitShare = Notification.Name("didAcceptCloudKitShare")
    /// Posted once an accepted invitation has been joined and the membership
    /// row written.
    static let didJoinClassroom = Notification.Name("didJoinClassroom")
}

// MARK: - Invitation Inbox

/// Holds an accepted share invitation until a `ClassroomSharingService` can
/// act on it.
///
/// The system can hand the invitation over before any service exists: tapping
/// the link can be what launches the app, and the notebook only builds its
/// service when something asks for it. A bare notification posted then would
/// reach nobody, so the invitation waits here, and whichever comes second — the
/// invitation or the service — picks it up. `take()` hands it out once.
enum ShareInvitationInbox {
    private static var pending: CKShare.Metadata?

    static var hasPending: Bool { pending != nil }

    static func deliver(_ metadata: CKShare.Metadata) {
        pending = metadata
        NotificationCenter.default.post(name: .didAcceptCloudKitShare, object: nil)
    }

    static func take() -> CKShare.Metadata? {
        defer { pending = nil }
        return pending
    }
}
