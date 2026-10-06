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
    let context: NSManagedObjectContext

    // MARK: - Observable State

    private(set) var currentRole: CDClassroomMembership.ClassroomRole = .leadGuide
    private(set) var participants: [CKShare.Participant] = []
    private(set) var isSharing: Bool = false
    private(set) var shareError: String?
    private(set) var currentShare: CKShare?
    /// True while an opened invitation is being joined, which can take a
    /// while; the Daybook Assistant shows "Joining your classroom…". Gives
    /// up after `joinTimeout`.
    private(set) var isJoining = false
    /// Numbers each join (`beginJoin`).
    @ObservationIgnored private var joinAttempt = 0

    /// The share entry of whoever is using this device, so the members list
    /// can mark its own row. CloudKit withholds your own name components, which
    /// otherwise leaves you as an anonymous entry in your own classroom. By
    /// participant ID: your own entry's record name is CloudKit's stand-in
    /// `__defaultOwner__` on every device (`ClassroomIdentity.realRecordName`).
    private(set) var currentUserParticipantID: String?

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
        // This device's own record name comes from `ClassroomIdentity
        // .refreshRecordName()`, never from here: the share gives the stand-in.
        let participantID = share?.currentUserParticipant?.participantID
        if currentUserParticipantID != participantID { currentUserParticipantID = participantID }
    }

    /// Accepts an incoming share invitation.
    /// Called via notification when user taps a share link.
    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let store = sharedStore else {
            Self.logger.error("Cannot accept share: shared store not found")
            shareError = "Couldn't join the classroom on this device. Quit and reopen the app, "
                + "then open the invitation again."
            ToastService.shared.showError(shareError ?? "")
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

    /// Resynchronizes published share state once the share turns out to be
    /// gone: deleted on another device (an older build's system sharing sheet,
    /// whose Stop Sharing deletes it). This app's own Stop Sharing removes
    /// everyone and keeps the share (`removeAllMembers`).
    ///
    /// The service's published state (`currentShare`/`isSharing`/
    /// `participants`) would otherwise keep reporting the dead share until the
    /// next `fetchExistingShare` call. Clearing eagerly also prevents further
    /// exports from targeting the deleted share's zone through stale cached state.
    func handleSharingStopped() {
        Self.logger.info("The classroom share is gone; resynchronizing share state")
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
        loadCurrentMembership() // a row synced in after init left a stale role
        guard currentRole == .assistant else {
            Self.logger.warning("Only assistants can leave a classroom")
            return
        }

        // Which share to purge, or why not to leave yet: see `shareToLeave`.
        if let store = sharedStore {
            let shares = try container.fetchShares(in: store)
            let pinned = currentShare ?? CDClassroomMembership.classroomShare(among: shares, in: context)
            let holdsClassroom = Self.holdsClassroom(store, in: context)
            if let zoneID = try Self.shareToLeave(pinned: pinned, among: shares, holdsClassroom: holdsClassroom)?
                .recordID.zoneID {
                Self.logger.notice("Purging shared zone: \(zoneID.zoneName, privacy: .public)")
                try await container.purgeObjectsAndRecordsInZone(with: zoneID, in: store)
            }
        }

        // Every assistant row, not just the newest: two iPhones joining before
        // either row synced leave two, and the older kept the device "joined".
        let request = CDClassroomMembership.ownRowsRequest()
        request.predicate = NSPredicate(
            format: "roleRaw == %@", CDClassroomMembership.ClassroomRole.assistant.rawValue
        )
        let rows = context.safeFetch(request)
        if !rows.isEmpty {
            rows.forEach(context.delete)
            // The class is already gone, so the deletes stay pending for the next save.
            guard ClassroomRepository(context: context).save(reason: "Leave classroom") else {
                throw ClassroomLeaveError.notSaved
            }
        }

        currentShare = nil
        participants = []
        isSharing = false
        currentRole = .leadGuide
        Self.logger.info("Left classroom successfully")
    }

    // MARK: - Private

    private var sharedStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            store.configurationName == CoreDataStack.sharedConfiguration
        }
    }

    /// Re-reads the role from the current membership row (the Assistant calls
    /// it when a row arrives by sync rather than by accepting here).
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
        let attempt = beginJoin()
        Task { [weak self] in
            try? await Task.sleep(for: Self.joinTimeout)
            self?.joinTimedOut(attempt)
        }
        Task {
            defer { endJoin(attempt) }
            do {
                try await acceptShare(metadata: metadata)
            } catch {
                Self.logger.error("Share acceptance failed: \(error.localizedDescription)")
                // A later invitation's join owns the screen now.
                guard attempt == joinAttempt else { return }
                let message = AppErrorMessages.joinMessage(for: error) + " " + Self.joinAdvice(for: error)
                shareError = message
                ToastService.shared.showError(message)
            }
        }
    }

    // MARK: - Join timeout

    /// Starts showing a join; its number keeps a later invitation's join from
    /// being ended by an earlier one's timeout or finish.
    func beginJoin() -> Int {
        joinAttempt += 1
        isJoining = true
        shareError = nil
        return joinAttempt
    }

    /// CloudKit's accept has no timeout and can't be cancelled, so a join
    /// that never answered left "Joining your classroom…" up for good. After
    /// `joinTimeout` the screen lets go; a late success still saves the
    /// membership row and posts `.didJoinClassroom`.
    func joinTimedOut(_ attempt: Int) {
        guard attempt == joinAttempt, isJoining else { return }
        Self.logger.error("Joining the classroom timed out; the accept may still finish")
        isJoining = false
        shareError = Self.joinTimeoutMessage
    }

    func endJoin(_ attempt: Int) {
        if attempt == joinAttempt { isJoining = false }
    }
}
