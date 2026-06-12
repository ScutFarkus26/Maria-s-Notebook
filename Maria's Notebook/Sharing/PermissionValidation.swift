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
