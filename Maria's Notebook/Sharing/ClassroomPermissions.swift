import Foundation

/// Role-based permission matrix for classroom sharing.
///
/// Determines which Core Data entities each role can read/write.
/// Lead guides have full access; assistants can read everything
/// but only write to a limited set of entities.
///
/// Note: These permissions gate UI actions (edit buttons, save operations).
/// The actual store routing (private vs shared) is handled by CoreDataStack.
enum ClassroomPermissions {

    /// Entity names that assistants are allowed to write/delete.
    /// Lead guides can write to all entities.
    private static let assistantWritableEntities: Set<String> = [
        "AttendanceRecord",
        "Note",
        "NoteStudentLink",
        "WorkCheckIn"
    ]

    /// Whether the given role can write (create/update) the named entity.
    static func canWrite(
        entityName: String,
        role: CDClassroomMembership.ClassroomRole
    ) -> Bool {
        switch role {
        case .leadGuide:
            return true
        case .assistant:
            return assistantWritableEntities.contains(entityName)
        }
    }

    /// Whether the given role can delete the named entity.
    static func canDelete(
        entityName: String,
        role: CDClassroomMembership.ClassroomRole
    ) -> Bool {
        canWrite(entityName: entityName, role: role)
    }

    /// Entity names the assistant role is allowed to write.
    /// Lead guides can write all entities (use `canWrite` to check).
    static func assistantWritableEntityNames() -> Set<String> {
        assistantWritableEntities
    }

    /// Whether the given role can manage sharing (invite/remove participants).
    static func canManageSharing(
        role: CDClassroomMembership.ClassroomRole
    ) -> Bool {
        role == .leadGuide
    }
}
