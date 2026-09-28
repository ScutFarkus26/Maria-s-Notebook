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
/// Sharing stays on throughout: the share is what keeps the lead guide's
/// records syncing (see `ensureShareExistsOnLaunch`), so "stop sharing" here
/// means removing everyone else, never deleting the share.
extension ClassroomSharingService {

    enum MemberError: LocalizedError {
        case noShare
        case emptyAddress
        case noAccount(String)

        var errorDescription: String? {
            switch self {
            case .noShare:
                return "Your classroom isn't shared yet. Try again once sync has finished."
            case .emptyAddress:
                return "Enter an email address or phone number."
            case .noAccount(let address):
                return "No Apple Account was found for \(address)."
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
        participant.permission = permission
        share.addParticipant(participant)
        try await save(share)
    }

    func removeMember(_ participant: CKShare.Participant) async throws {
        try await removeMembers { $0.participantID == participant.participantID }
    }

    /// Everyone but the owner loses access; the classroom stays shared.
    func removeAllMembers() async throws {
        try await removeMembers { _ in true }
    }

    // MARK: - Private

    private func removeMembers(where matches: (CKShare.Participant) -> Bool) async throws {
        guard let share = try fetchExistingShare() else { throw MemberError.noShare }
        let leaving = share.participants.filter { $0.role != .owner && matches($0) }
        guard !leaving.isEmpty else { return }
        leaving.forEach(share.removeParticipant)
        try await save(share)
    }

    private func save(_ share: CKShare) async throws {
        guard let store = container.persistentStoreCoordinator.persistentStores
            .first(where: { $0.configurationName == CoreDataStack.privateConfiguration })
        else { throw MemberError.noShare }
        let saved = try await container.persistUpdatedShare(share, in: store)
        updateShareState(saved)
        try refreshParticipants()
    }

    private var cloudKitContainer: CKContainer {
        CloudKitConfigurationService.getContainerID().map(CKContainer.init(identifier:)) ?? .default()
    }
}
