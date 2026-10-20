import Foundation
import CoreData
import CloudKit
import OSLog

// Joining a classroom from an invitation: the accept, its time limit, and
// what a failure says. Both apps compile it (the Daybook Assistant lists it
// by path in project.pbxproj, beside ClassroomSharingService.swift).

extension ClassroomSharingService {
    private static let joinLogger = Logger.classroomSharing

    /// Accepts an incoming share invitation.
    /// Called via notification when user taps a share link.
    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let store = sharedStore else {
            Self.joinLogger.error("Cannot accept share: shared store not found")
            shareError = "Couldn't join the classroom on this device. Quit and reopen the app, "
                + "then open the invitation again."
            ToastService.shared.showError(shareError ?? "")
            return
        }
        // Another guide's class while this device is still in one: joining
        // would mix the two in one store (`ClassroomJoinRefusal`).
        if await isInAnotherGuidesClass(than: metadata, sharedStore: store) {
            throw ClassroomJoinRefusal.alreadyInAClass
        }

        Self.joinLogger.info("Accepting CloudKit share invitation...")
        try await container.acceptShareInvitations(from: [metadata], into: store)
        // A rebuilt stack took this join over meanwhile (`letGoOfJoin`): this
        // stack's stores are gone, and the new one's accept writes the row.
        try Task.checkCancellation()

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
        // Read off the main actor: the class's first download is under way,
        // and the read waits while it holds the store (bug hunt 2026-10-20 #10).
        do {
            try await refreshParticipantsOffMain()
        } catch {
            Self.joinLogger.error("Joined, but reading the participants failed: \(error.localizedDescription)")
        }
        Self.joinLogger.info("Share accepted successfully")
        NotificationCenter.default.post(name: .didJoinClassroom, object: nil)
    }

    /// Takes the invitation waiting in `ShareInvitationInbox`, if any, and
    /// joins its classroom. A service with no shared store (the Sample Class)
    /// leaves the invitation for the real notebook's service.
    func acceptPendingInvitation() {
        guard sharedStore != nil, let metadata = ShareInvitationInbox.take() else { return }
        let attempt = beginJoin(metadata)
        Task { [weak self] in
            try? await Task.sleep(for: Self.joinTimeout)
            self?.joinTimedOut(attempt)
        }
        joinTask = Task {
            defer { endJoin(attempt) }
            do {
                try await acceptShare(metadata: metadata)
            } catch {
                joinFailed(error, invitation: metadata, attempt: attempt)
            }
        }
    }

    /// A join that didn't go through. Another guide's class is said where
    /// she is, over the class's own screens: the join page isn't showing,
    /// and would keep it after a Leave. Anything else shows on the join page,
    /// unless a later invitation's join owns the screen now, or the Daybook
    /// Assistant keeps the invitation for a rebuilt stack
    /// (`keepsFailedInvitation`).
    func joinFailed(_ error: Error, invitation: CKShare.Metadata?, attempt: Int) {
        if let refusal = error as? ClassroomJoinRefusal {
            Self.joinLogger.notice("Refused an invitation to another guide's class while in one")
            if attempt == joinAttempt { ToastService.shared.showError(refusal.message) }
            return
        }
        Self.joinLogger.error("Share acceptance failed: \(error.localizedDescription)")
        guard attempt == joinAttempt else { return }
        if keepsFailedInvitation {
            failedInvitation = invitation
            Self.joinLogger.notice("The join failed while the stack waits to be rebuilt; it goes again after")
            return
        }
        let message = AppErrorMessages.joinMessage(for: error) + " " + Self.joinAdvice(for: error)
        shareError = message
        ToastService.shared.showError(message)
    }
}

// MARK: - Join timeout

extension ClassroomSharingService {
    /// Starts showing a join; its number keeps a later invitation's join from
    /// being ended by an earlier one's timeout or finish.
    func beginJoin(_ invitation: CKShare.Metadata? = nil) -> Int {
        joinAttempt += 1
        isJoining = true
        acceptIsRunning = true
        runningInvitation = invitation
        shareError = nil
        failedInvitation = nil
        return joinAttempt
    }

    /// CloudKit's accept has no timeout and can't be cancelled, so a join
    /// that never answered left "Joining your classroom…" up for good. After
    /// `joinTimeout` the screen lets go; a late success still saves the
    /// membership row and posts `.didJoinClassroom`.
    ///
    /// Not while a rebuild waits for the join (`keepsFailedInvitation`): the
    /// wait decides then. Timed out here, the wait ended at once and the
    /// stack came off under the running accept (2026-10-20 review b,
    /// item 2).
    func joinTimedOut(_ attempt: Int) {
        guard attempt == joinAttempt, isJoining, !keepsFailedInvitation else { return }
        Self.joinLogger.error("Joining the classroom timed out; the accept may still finish")
        isJoining = false
        shareError = Self.joinTimeoutMessage
    }

    /// The accept came back, however it went.
    func endJoin(_ attempt: Int) {
        guard attempt == joinAttempt else { return }
        isJoining = false
        acceptIsRunning = false
        runningInvitation = nil
        joinTask = nil
    }

    /// A rebuilt stack takes this join over (`AssistantBootstrapper
    /// .waitForJoinBeforeRebuild`). The accept still running here can't be
    /// stopped, but its number is passed and its task cancelled, so its late
    /// answer writes nothing and says nothing.
    func letGoOfJoin() {
        joinAttempt += 1
        joinTask?.cancel()
        joinTask = nil
        isJoining = false
        acceptIsRunning = false
        runningInvitation = nil
        failedInvitation = nil
    }
}
