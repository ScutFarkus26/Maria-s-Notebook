import CloudKit
import Foundation
import OSLog

/// Who this device's user is, for attributing what they change.
///
/// Both values are deliberately device-local. The record name is whatever
/// CloudKit calls this iCloud account in this container, and the display name
/// is what the person typed on their own device — CloudKit withholds your own
/// name components from you, so a name can only come from the person themselves.
/// What everyone else sees is the classroom's shared list (`ClassroomNames`),
/// which each person's row joins once the record name is known.
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
    /// per launch; offline, it keeps what was saved before. Callers then run
    /// `ClassroomNames.writeWaitingName`, which writes a name typed before the
    /// record name was known.
    ///
    /// The first call also starts following Apple Account changes
    /// (`followAccountChanges`), and noting CloudKit's imports for
    /// `ClassroomNames.Arrival`, as early in the launch as both apps get.
    static func refreshRecordName(container: CKContainer = CloudKitConfigurationService.container) async {
        // Unit tests never ask iCloud.
        guard !isRunningUnitTests else { return }
        ClassroomNames.Arrival.shared.start()
        followAccountChanges(container: container)
        await readRecordName(from: container)
    }

    private static func readRecordName(from container: CKContainer) async {
        // Saved by the last launch, or the account before a change.
        let before = currentUserRecordName
        do {
            let recordID = try await container.userRecordID()
            currentUserRecordName = recordID.recordName
            // Another account signed in while the notebook was closed.
            forgetWaitingName(ifAnotherAccountThan: before)
        } catch {
            let detail = error.localizedDescription
            logger.notice("Couldn't read this account's CloudKit record name: \(detail, privacy: .public)")
        }
    }

    // MARK: - Account changes

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The account-change observer, once `followAccountChanges` has started it.
    private static var accountObserver: (any NSObjectProtocol)?

    /// Reads the record name again whenever the Apple Account changes
    /// (`.CKAccountChanged`): the saved one goes at once, so nothing new is
    /// stamped with the last account's ID (the "you" and name rows), and the
    /// new account's is asked for. Signed out, or offline, it stays unknown
    /// until an answer comes; changes meanwhile fall back to role and name,
    /// as before it was known. Started by the first `refreshRecordName()`;
    /// never under unit tests.
    static func followAccountChanges(container: CKContainer = CloudKitConfigurationService.container) {
        guard accountObserver == nil, !isRunningUnitTests else { return }
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                _ = Task { await accountChanged { await readRecordName(from: container) } }
            }
        }
    }

    /// What an account change does: forget the saved record name, then read
    /// the new one with `reread`. Tests pass their own read.
    ///
    /// On the notebook, a name waiting to go into the classroom's list was
    /// typed under the account before; once the read confirms another
    /// account, it's dropped (`ClassroomNames.forgetWaitingName`). It used to
    /// go into the new account's row (2026-10-09 hunt, #5). Not when the read
    /// finds none (signed out, offline, not ready) or the same account: the
    /// name keeps waiting. The Assistant does this itself, asking her name
    /// again (`AssistantBootstrapper`).
    static func accountChanged(reread: () async -> Void) async {
        logger.notice("The Apple Account changed; reading this account's record name again")
        let before = currentUserRecordName
        currentUserRecordName = nil
        await reread()
        forgetWaitingName(ifAnotherAccountThan: before)
    }

    /// On the notebook, drops a waiting name once the record name read is
    /// known and another than `before`. Both must be known: an account that
    /// couldn't be read is no reason to drop it, as on her phone
    /// (`AssistantNameStore.isAnotherAccount`), which does this itself.
    private static func forgetWaitingName(ifAnotherAccountThan before: String?) {
        #if !ASSISTANT_APP
        guard let before, let now = currentUserRecordName, now != before else { return }
        ClassroomNames.forgetWaitingName()
        #endif
    }

    /// The label this person wants beside their marks. Empty is stored as nil so
    /// a cleared field doesn't attribute marks to a blank name.
    ///
    /// Also where a name typed before `currentUserRecordName` is known waits
    /// (`nameWaitingAs`) until `ClassroomNames.writeWaitingName` puts it in the
    /// classroom's list.
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

    /// Per CloudKit environment, like the record name it waits for.
    private static var nameWaitingKey: String { CloudKitEnvironment.scoped("ClassroomIdentity.nameWaitingAs") }

    /// Set while a name typed on this device (in `displayName`, or cleared)
    /// waits for this account's record name before it can go into the
    /// classroom's list: the role it was typed as. Nil when nothing waits.
    /// Only `ClassroomNames` sets it; it's cleared when another account
    /// signs in (`AssistantNameStore.forgetForNewAccount` on her phone,
    /// `ClassroomNames.forgetWaitingName` on the notebook).
    static var nameWaitingAs: CDClassroomMembership.ClassroomRole? {
        get { UserDefaults.standard.string(forKey: nameWaitingKey).flatMap(CDClassroomMembership.ClassroomRole.init) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: nameWaitingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: nameWaitingKey)
                UserDefaults.standard.removeObject(forKey: nameWaitingForKey)
            }
        }
    }

    /// Per CloudKit environment, beside `nameWaitingAs`.
    private static var nameWaitingForKey: String { CloudKitEnvironment.scoped("ClassroomIdentity.nameWaitingFor") }

    /// The account (record name) a waiting name was typed under, when it was
    /// known then; nil when it wasn't, and for names waiting from before this
    /// was kept. Set after `nameWaitingAs`, which clears it whenever nothing
    /// waits. `ClassroomNames.writeWaitingName` writes a waiting name only
    /// under this account, and drops it under another (2026-10-09 review).
    static var nameWaitingFor: String? {
        get { realRecordName(UserDefaults.standard.string(forKey: nameWaitingForKey)) }
        set {
            if let real = realRecordName(newValue) {
                UserDefaults.standard.set(real, forKey: nameWaitingForKey)
            } else {
                UserDefaults.standard.removeObject(forKey: nameWaitingForKey)
            }
        }
    }
}
