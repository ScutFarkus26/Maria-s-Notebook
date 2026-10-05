import CloudKit
import Foundation
import OSLog

/// Who this device's user is, for attributing what they change.
///
/// Both values are deliberately device-local. The record name is whatever
/// CloudKit calls this iCloud account in this container, and the display name
/// is what the person typed on their own device — CloudKit withholds your own
/// name components from you, so a name can only come from the person themselves.
enum ClassroomIdentity {

    private static let recordNameKey = UserDefaultsKeys.classroomIdentityRecordName
    private static let displayNameKey = UserDefaultsKeys.classroomIdentityDisplayName

    private static let logger = Logger.classroomSharing

    /// This account's CloudKit user record name in the classroom's container,
    /// from `refreshRecordName()`. Never a stand-in: one saved by an older
    /// build reads as nil, so changes fall back to role and name.
    static var currentUserRecordName: String? {
        get { realRecordName(UserDefaults.standard.string(forKey: recordNameKey)) }
        set {
            if let real = realRecordName(newValue) {
                UserDefaults.standard.set(real, forKey: recordNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: recordNameKey)
            }
        }
    }

    /// A record name that names one person, or nil.
    ///
    /// CloudKit calls whoever is using the device `__defaultOwner__`
    /// (`CKCurrentUserDefaultName`) on their own share entry, so every device
    /// that saved that one thought it was the same person, and the guide's
    /// changes read "you" on an assistant's phone. "unknown" and "self" are
    /// what membership rows hold where the share gave no name. Stamps already
    /// saved with any of these are read as having no ID.
    nonisolated static func realRecordName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return [CKCurrentUserDefaultName, "unknown", "self"].contains(name) ? nil : name
    }

    /// Asks CloudKit who this account is in the classroom's container (never
    /// `CKContainer.default()`, whose record names differ) and saves it. Once
    /// per launch; offline, it keeps what was saved before.
    static func refreshRecordName(container: CKContainer = CloudKitConfigurationService.container) async {
        // Unit tests never ask iCloud.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        do {
            let recordID = try await container.userRecordID()
            currentUserRecordName = recordID.recordName
        } catch {
            logger.notice("Couldn't read this account's CloudKit record name: \(error.localizedDescription, privacy: .public)")
        }
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
