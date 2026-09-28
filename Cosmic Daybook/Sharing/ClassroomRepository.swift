import Foundation
import OSLog
import CoreData

struct ClassroomRepository: SavingRepository {
    typealias Model = CDClassroomMembership

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    func fetchMembership(id: UUID) -> CDClassroomMembership? { fetch(id: id) }

    /// This device's current membership row (see `CDClassroomMembership.current`).
    func fetchCurrentMembership() -> CDClassroomMembership? {
        CDClassroomMembership.current(in: context)
    }

    // MARK: - Create

    @discardableResult
    func createMembership(
        classroomZoneID: String,
        role: CDClassroomMembership.ClassroomRole,
        ownerIdentity: String
    ) -> CDClassroomMembership {
        let membership = CDClassroomMembership(context: context)
        // Pin this to the private store. A membership row states what *this*
        // device's user is, so it must never reach the classroom share — a row
        // that synced would answer `currentRole` on someone else's device.
        // ClassroomMembership is private-only since schema 9; the assignment
        // only matters in the two-store layout, and says so explicitly.
        if let coordinator = context.persistentStoreCoordinator,
           coordinator.persistentStores.count > 1,
           let privateStore = coordinator.persistentStores.first(where: {
               $0.configurationName == CoreDataStack.privateConfiguration
           }) {
            context.assign(membership, to: privateStore)
        }
        membership.classroomZoneID = classroomZoneID
        membership.role = role
        membership.ownerIdentity = ownerIdentity
        Self.logger.info("Created ClassroomMembership: role=\(role.rawValue), zone=\(classroomZoneID)")
        return membership
    }

    /// Writes the pin: the classroom share's zone, on this device's current
    /// row when it has the same role, or on a new row. Called when the lead
    /// guide sets up sharing (a re-share included) and when an assistant
    /// accepts an invitation, so the next reader finds exactly this zone.
    @discardableResult
    func pinClassroom(
        zoneName: String,
        role: CDClassroomMembership.ClassroomRole,
        ownerIdentity: String
    ) -> CDClassroomMembership {
        if let current = fetchCurrentMembership(), current.role == role {
            current.classroomZoneID = zoneName
            current.ownerIdentity = ownerIdentity
            current.modifiedAt = Date()
            Self.logger.info("Pinned classroom zone \(zoneName, privacy: .public) (\(role.rawValue, privacy: .public))")
            return current
        }
        return createMembership(classroomZoneID: zoneName, role: role, ownerIdentity: ownerIdentity)
    }

    // MARK: - Delete

    func deleteMembership(id: UUID) {
        guard let membership = fetchMembership(id: id) else {
            Self.logger.warning("Cannot delete: membership \(id) not found")
            return
        }
        context.delete(membership)
        Self.logger.info("Deleted ClassroomMembership \(id)")
    }
}
