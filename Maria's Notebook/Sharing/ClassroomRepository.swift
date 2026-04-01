import Foundation
import OSLog
import CoreData

@MainActor
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

    func fetchMembership(id: UUID) -> CDClassroomMembership? {
        let request = CDFetchRequest(CDClassroomMembership.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    func fetchMemberships(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [
            NSSortDescriptor(key: "joinedAt", ascending: false)
        ]
    ) -> [CDClassroomMembership] {
        let request = CDFetchRequest(CDClassroomMembership.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        return context.safeFetch(request)
    }

    /// Returns the first classroom membership, representing the current classroom.
    func fetchCurrentMembership() -> CDClassroomMembership? {
        let request = CDFetchRequest(CDClassroomMembership.self)
        request.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: false)]
        request.fetchLimit = 1
        return context.safeFetchFirst(request)
    }

    // MARK: - Create

    @discardableResult
    func createMembership(
        classroomZoneID: String,
        role: CDClassroomMembership.ClassroomRole,
        ownerIdentity: String
    ) -> CDClassroomMembership {
        let membership = CDClassroomMembership(context: context)
        membership.classroomZoneID = classroomZoneID
        membership.role = role
        membership.ownerIdentity = ownerIdentity
        Self.logger.info("Created ClassroomMembership: role=\(role.rawValue), zone=\(classroomZoneID)")
        return membership
    }

    // MARK: - Update

    @discardableResult
    func updateRole(id: UUID, role: CDClassroomMembership.ClassroomRole) -> Bool {
        guard let membership = fetchMembership(id: id) else {
            Self.logger.warning("Cannot update role: membership \(id) not found")
            return false
        }
        membership.role = role
        membership.modifiedAt = Date()
        return save(reason: "Update classroom role")
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
