import Foundation
import CoreData

/// Error thrown when an assistant attempts to write an entity they don't have permission for.
enum PermissionError: LocalizedError {
    case insufficientRole(entityName: String, role: CDClassroomMembership.ClassroomRole)

    var errorDescription: String? {
        switch self {
        case .insufficientRole(let entityName, let role):
            return "Role '\(role.rawValue)' does not have write permission for '\(entityName)'."
        }
    }
}

extension NSManagedObjectContext {
    /// Validates that the current user's role has permission to save all pending changes.
    /// Call before `save()` to enforce permissions at the data layer.
    func validatePermissionsBeforeSave(role: CDClassroomMembership.ClassroomRole) throws {
        guard role != .leadGuide else { return }

        for object in insertedObjects.union(updatedObjects) {
            let entityName = object.entity.name ?? ""
            guard ClassroomPermissions.canWrite(entityName: entityName, role: role) else {
                throw PermissionError.insufficientRole(entityName: entityName, role: role)
            }
        }
    }
}
