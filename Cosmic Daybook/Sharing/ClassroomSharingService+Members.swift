import Foundation
import CoreData
import CloudKit

/// Adding and removing classroom members without the system sharing UI.
///
/// macOS has no `UICloudSharingController`, and the share popover
/// `NSSharingServicePicker` offers for a registered `CKShare` comes up empty for
/// this app (the share sheet logs "No items to share after sandbox filtering").
/// The Mac's Settings → Classroom sheet manages members through these instead.
///
/// Sharing stays on throughout: the one classroom share is set up once and
/// pinned (see `setUpClassroomSharing`), so "stop sharing" here means removing
/// everyone else, never deleting the share — a new one would be a second zone.
extension ClassroomSharingService {

    // MARK: - Permission Queries

    func canManageSharing() -> Bool {
        ClassroomPermissions.canManageSharing(role: currentRole)
    }

    enum MemberError: LocalizedError {
        case noShare
        case emptyAddress
        case noAccount(String)
        case alreadyInvited(String)
        case alreadyMember(String)

        var errorDescription: String? {
            switch self {
            case .noShare:
                return "Your classroom isn't shared yet. Try again once sync has finished."
            case .emptyAddress:
                return "Enter an email address or phone number."
            case .noAccount(let address):
                return "No Apple Account was found for \(address). Check the address and try again."
            case .alreadyInvited(let address):
                return "\(address) is already invited. Send them the classroom link; "
                    + "they'll be in once they open it and accept."
            case .alreadyMember(let address):
                return "\(address) is already in your classroom."
            }
        }
    }

    /// Adds the person with this Apple Account email or phone number. CloudKit
    /// sends nothing itself: they still need the classroom link, which only
    /// opens for people added here.
    func addMember(_ address: String, permission: CKShare.ParticipantPermission) async throws {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw MemberError.emptyAddress }
        guard let share = try fetchExistingShare() else { throw MemberError.noShare }

        let lookup = address.contains("@")
            ? CKUserIdentity.LookupInfo(emailAddress: address)
            : CKUserIdentity.LookupInfo(phoneNumber: address)
        let results = try await cloudKitContainer.shareParticipants(for: [lookup])
        guard let participant = try results.values.first?.get() else {
            throw MemberError.noAccount(address)
        }
        // Adding the same Apple Account twice is a silent no-op on the share,
        // so say so instead of reporting a success that changed nothing.
        if let existing = share.participants.first(where: { isSamePerson($0, participant) }),
           existing.acceptanceStatus != .removed {
            throw existing.acceptanceStatus == .accepted
                ? MemberError.alreadyMember(address)
                : MemberError.alreadyInvited(address)
        }
        participant.permission = permission
        share.addParticipant(participant)
        do {
            try await save(share)
        } catch let error where Self.isAlreadyInvited(error) {
            // iOS/macOS 26: the server refuses a second invitation while the
            // first is still waiting to be accepted.
            throw MemberError.alreadyInvited(address)
        }
    }

    func removeMember(_ participant: CKShare.Participant) async throws {
        try await removeMembers { $0.participantID == participant.participantID }
    }

    /// Everyone but the owner loses access; the classroom stays shared.
    func removeAllMembers() async throws {
        try await removeMembers { _ in true }
    }

    // MARK: - Private

    private func isSamePerson(_ lhs: CKShare.Participant, _ rhs: CKShare.Participant) -> Bool {
        if let left = lhs.userIdentity.userRecordID, let right = rhs.userIdentity.userRecordID {
            return left == right
        }
        return lhs.participantID == rhs.participantID
    }

    /// `CKError.participantAlreadyInvited`, found directly, inside a partial
    /// failure, or under the Core Data error `persistUpdatedShare` wraps it in.
    nonisolated static func isAlreadyInvited(_ error: any Error) -> Bool {
        if let ckError = error as? CKError {
            if ckError.code == .participantAlreadyInvited { return true }
            if let partials = ckError.partialErrorsByItemID?.values,
               partials.contains(where: isAlreadyInvited) {
                return true
            }
        }
        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? any Error {
            return isAlreadyInvited(underlying)
        }
        return false
    }

    private func removeMembers(where matches: (CKShare.Participant) -> Bool) async throws {
        guard let share = try fetchExistingShare() else { throw MemberError.noShare }
        let leaving = share.participants.filter { $0.role != .owner && matches($0) }
        guard !leaving.isEmpty else { return }
        leaving.forEach(share.removeParticipant)
        try await save(share)
    }

    private func save(_ share: CKShare) async throws {
        guard let storeIdentifier = container.persistentStoreCoordinator.persistentStores
            .first(where: { $0.configurationName == CoreDataStack.privateConfiguration })?.identifier
        else { throw MemberError.noShare }
        // Off the main actor: the call blocks its thread until the export resolves.
        let saved = try await ClassroomShareAttach.persistUpdatedShareOffMain(
            share, storeIdentifier: storeIdentifier, container: container
        )
        updateShareState(saved)
        try refreshParticipants()
    }

    private var cloudKitContainer: CKContainer {
        CloudKitConfigurationService.container
    }
}
