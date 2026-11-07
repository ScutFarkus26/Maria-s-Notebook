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
    /// only. Set by `ClassroomSharingService` from what the share says
    /// (`readPermission`), never guessed from a failed save. While
    /// set, an assistant writes nothing: her marks saved on the phone and
    /// never reached the guide (bug hunt 2026-11-02 #29).
    ///
    /// Kept on the device too, and read from there at launch: Siri can open
    /// the Assistant cold and change Restock before `readPermission` has
    /// run, and it used to find false and make a change that never reached
    /// the guide (bug hunt 2026-11-03 #7). Leaving the class sets it false,
    /// which forgets it.
    ///
    /// Every set is an answer, so it also ends `viewOnlyIsUnconfirmed`.
    static var shareIsViewOnly = savedViewOnly(in: .standard).viewOnly {
        didSet {
            viewOnlyIsUnconfirmed = false
            UserDefaults.standard.removeObject(forKey: oldViewOnlyKey)
            if shareIsViewOnly {
                UserDefaults.standard.set(true, forKey: viewOnlyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: viewOnlyKey)
            }
        }
    }

    /// Where the last View only answer is kept, since the rule of
    /// 2026-11-06 that only the share's own word decides it.
    nonisolated static let viewOnlyKey = "ClassroomPermissions.shareIsViewOnly.v2"
    /// Where the old rule kept it. That rule also counted the store-wide
    /// `canModifyManagedObjects`, which said View only for assistants the
    /// share let make changes, and a wrong answer saved under it cleared
    /// only when the share said read-write (bug hunt 2026-11-06 #7).
    nonisolated static let oldViewOnlyKey = "ClassroomPermissions.shareIsViewOnly"

    /// A View only kept under the old rule and not yet read again from the
    /// share. It still holds writes back: a View-only phone's write saves
    /// on the phone and never reaches the guide, since the store doesn't
    /// refuse it. The first read of the share drops it, even one that says
    /// nothing (`dropUnconfirmedViewOnly`); an answer replaces it. Read
    /// once at launch; tests set it.
    static var viewOnlyIsUnconfirmed = savedViewOnly(in: .standard).unconfirmed

    /// What `defaults` kept: View only under the new key, or under the old
    /// one only (unconfirmed, and still View only until the share is read).
    nonisolated static func savedViewOnly(in defaults: UserDefaults) -> (viewOnly: Bool, unconfirmed: Bool) {
        if defaults.bool(forKey: viewOnlyKey) { return (true, false) }
        let old = defaults.bool(forKey: oldViewOnlyKey)
        return (old, old)
    }

    /// The share was read: a View only kept only under the old rule goes.
    /// True if it did.
    @discardableResult
    static func dropUnconfirmedViewOnly() -> Bool {
        guard viewOnlyIsUnconfirmed else { return false }
        shareIsViewOnly = false
        return true
    }

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
