import Foundation

/// Role-based permission matrix for classroom sharing.
///
/// Determines which Core Data entities each role can read/write.
/// Lead guides have full access; assistants can read everything but write
/// only what the Daybook Assistant does: attendance (the day's records and the
/// front-desk email sends), Restock (staples, their history and the needs,
/// since schema 15) and her own name in the classroom's list (schema 16). Only
/// the guide sends the order email, and each person writes only their own
/// name; those are the app's rules, not this matrix's. (Per-category toggles
/// the guide could set lived in iCloud key-value storage, which never reached
/// an assistant's own Apple Account; they were removed on 2026-09-30. Letting
/// assistants write more would need the choice in the classroom share itself.)
///
/// These permissions gate UI actions (edit buttons, save operations).
/// The actual store routing (private vs shared) is handled by CoreDataStack.
enum ClassroomPermissions {

    /// The guide added this device's account to the classroom share as View
    /// only. Set by `ClassroomSharingService` from what Core Data and the
    /// share say (`readPermission`), never guessed from a failed save. While
    /// set, an assistant writes nothing: her marks saved on the phone and
    /// never reached the guide (bug hunt 2026-11-02 #29).
    ///
    /// Kept on the device too, and read from there at launch: Siri can open
    /// the Assistant cold and change Restock before `readPermission` has
    /// run, and it used to find false and make a change that never reached
    /// the guide (bug hunt 2026-11-03 #7). Leaving the class sets it false,
    /// which forgets it.
    static var shareIsViewOnly = UserDefaults.standard.bool(forKey: viewOnlyKey) {
        didSet {
            if shareIsViewOnly {
                UserDefaults.standard.set(true, forKey: viewOnlyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: viewOnlyKey)
            }
        }
    }

    /// Where the last View only answer is kept.
    static let viewOnlyKey = "ClassroomPermissions.shareIsViewOnly"

    /// Whether the given role can write (create/update) the named entity.
    static func canWrite(
        entityName: String,
        role: CDClassroomMembership.ClassroomRole
    ) -> Bool {
        switch role {
        case .leadGuide:
            return true
        case .assistant:
            return !shareIsViewOnly && assistantWritableEntities.contains(entityName)
        }
    }

    /// The entities an assistant may create, update or delete.
    static let assistantWritableEntities: Set<String> = [
        "AttendanceRecord", "AttendanceEmailSend", "Supply", "SupplyTransaction", "OrderItem",
        "ClassroomPerson"
    ]

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
