import Foundation

/// Who this device's user is, for attributing what they change.
///
/// Both values are deliberately device-local. The record name is whatever
/// CloudKit calls this iCloud account in this container, and the display name
/// is what the person typed on their own device — CloudKit withholds your own
/// name components from you, so a name can only come from the person themselves.
enum ClassroomIdentity {

    private static let recordNameKey = UserDefaultsKeys.classroomIdentityRecordName
    private static let displayNameKey = UserDefaultsKeys.classroomIdentityDisplayName

    /// Stable CloudKit user record name, cached when participants are refreshed.
    static var currentUserRecordName: String? {
        get { UserDefaults.standard.string(forKey: recordNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordNameKey) }
    }

    /// The label this person wants beside their marks. Empty is stored as nil so
    /// a cleared field doesn't attribute marks to a blank name.
    static var displayName: String? {
        get {
            let stored = UserDefaults.standard.string(forKey: displayNameKey)?.trimmed()
            return (stored?.isEmpty ?? true) ? nil : stored
        }
        set {
            let trimmed = newValue?.trimmed()
            if let trimmed, !trimmed.isEmpty {
                UserDefaults.standard.set(trimmed, forKey: displayNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: displayNameKey)
            }
        }
    }
}
