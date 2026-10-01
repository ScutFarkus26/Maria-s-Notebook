import Foundation

/// Role-based permission matrix for classroom sharing.
///
/// Determines which Core Data entities each role can read/write.
/// Lead guides have full access; assistants can read everything but write
/// attendance only — the day's records and the front-desk email sends, which
/// is all the Daybook Assistant does. (Per-category toggles the guide could set
/// lived in iCloud key-value storage, which never reached an assistant's own
/// Apple Account; they were removed on 2026-09-30. Letting assistants write
/// more would need the choice in the classroom share itself.)
///
/// These permissions gate UI actions (edit buttons, save operations).
/// The actual store routing (private vs shared) is handled by CoreDataStack.
enum ClassroomPermissions {

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

    /// The entities an assistant may create, update or delete.
    static let assistantWritableEntities: Set<String> = ["AttendanceRecord", "AttendanceEmailSend"]

    /// Whether the given role can delete the named entity.
    static func canDelete(
        entityName: String,
        role: CDClassroomMembership.ClassroomRole
    ) -> Bool {
        canWrite(entityName: entityName, role: role)
    }

    /// Whether the given role can manage sharing (invite/remove participants).
    static func canManageSharing(
        role: CDClassroomMembership.ClassroomRole
    ) -> Bool {
        role == .leadGuide
    }
}
