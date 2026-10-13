import Foundation
import SwiftUI
import CoreData
#if os(iOS)
import MessageUI
#endif

/// Preference keys for Attendance Email feature.
/// - CDNote: Values are stored in UserDefaults via @AppStorage.
public enum AttendanceEmailPrefs {
    public static let enabledKey = "AttendanceEmail.enabled"
    public static let toKey = "AttendanceEmail.to"
    public static let fromKey = "AttendanceEmail.from" // iOS preferred sending address
    public static let nameOrderKey = "AttendanceEmail.nameOrder"
    public static let groupByLevelKey = "AttendanceEmail.groupByLevel"
    /// When the front desk needs it by, minutes after midnight; shared with the assistants.
    public static let deadlineKey = "AttendanceEmail.deadlineMinutes"
    /// How attendance goes to the school: an `AttendanceSendMethod` raw value
    /// (schema 18); shared with the assistants. Unset reads as email.
    public static let sendMethodKey = "AttendanceEmail.sendMethod"
    /// The school's ParentLocker host; shared with the assistants. Unset reads
    /// as `AttendanceEmailLog.defaultParentLockerSite`.
    public static let parentLockerSiteKey = "AttendanceEmail.parentLockerSite"
}

/// The guide's stored preferences, and prefilled mail senders built from them.
extension AttendanceEmail {
    public static func storedToAddress() -> String? {
        let s = SyncedPreferencesStore.shared.string(forKey: AttendanceEmailPrefs.toKey)?.trimmed()
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    public static func storedFromAddress() -> String? {
        let s = SyncedPreferencesStore.shared.string(forKey: AttendanceEmailPrefs.fromKey)?.trimmed()
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// Falls back to "First Last" so an unset preference reads the way the report always has.
    public static func storedNameOrder() -> AttendanceEmailNameOrder {
        let raw = SyncedPreferencesStore.shared.string(forKey: AttendanceEmailPrefs.nameOrderKey)
        return raw.flatMap(AttendanceEmailNameOrder.init(rawValue:)) ?? .firstLast
    }

    public static func storedGroupByLevel() -> Bool {
        SyncedPreferencesStore.shared.bool(forKey: AttendanceEmailPrefs.groupByLevelKey)
    }

    /// The guide's settings as the classroom share carries them. The switch
    /// reads as on until turned off, as the settings screen shows it. The
    /// recipients go as the addresses joined with ", " (`sharedAddressLine`),
    /// which every Assistant build reads, however they were typed. The method
    /// reads as email until the guide picks ParentLocker.
    static func storedSettings(from store: SyncedPreferencesStore = .shared) -> AttendanceEmailLog.Settings {
        AttendanceEmailLog.Settings(
            isEnabled: store.get(key: AttendanceEmailPrefs.enabledKey) as? Bool ?? true,
            toAddresses: sharedAddressLine(store.string(forKey: AttendanceEmailPrefs.toKey)),
            nameOrder: store.string(forKey: AttendanceEmailPrefs.nameOrderKey)
                .flatMap(AttendanceEmailNameOrder.init(rawValue:)) ?? .firstLast,
            groupByLevel: store.bool(forKey: AttendanceEmailPrefs.groupByLevelKey),
            deadlineMinutes: store.get(key: AttendanceEmailPrefs.deadlineKey) as? Int
                ?? AttendanceEmailLog.defaultDeadlineMinutes,
            sendMethod: AttendanceSendMethod(stored: store.string(forKey: AttendanceEmailPrefs.sendMethodKey)),
            parentLockerSite: AttendanceEmailLog.parentLockerHost(
                store.string(forKey: AttendanceEmailPrefs.parentLockerSiteKey)
            )
        )
    }

    /// The launch's write: the guide's settings go into the share only when it
    /// has none yet (an older notebook, a first launch since schema 12). Never
    /// over a row already there: this device's preferences may not have caught
    /// up with an edit made on another of the guide's devices (2026-10-05).
    /// Returns whether it wrote; the caller saves.
    @discardableResult
    static func shareSettingsIfMissing(
        in context: NSManagedObjectContext,
        settings: AttendanceEmailLog.Settings = AttendanceEmail.storedSettings(),
        firstDownloadPending: Bool = FirstDownloadGate.isPending()
    ) -> Bool {
        guard !firstDownloadPending else { return false }
        return AttendanceEmailLog.saveSettingsIfMissing(
            settings, role: CDClassroomMembership.currentRole(in: context), in: context
        )
    }

    // MARK: - Settings' writes (bug hunt 2026-10-13 afternoon, H1)

    /// This device's side of the guide's settings: its synced preferences
    /// (which the notebook's own email is written from) and where a write the
    /// share still owes is kept. Tests pass their own.
    struct DeviceSettings {
        /// The guide's preferences, as `storedSettings` reads them.
        var stored: () -> AttendanceEmailLog.Settings
        /// Copies a value into the guide's preferences.
        var setPreference: (_ key: String, _ value: Any) -> Void
        /// Where a pending write is kept: this device's own defaults.
        var defaults: UserDefaults

        static var thisDevice: Self {
            Self(
                stored: { AttendanceEmail.storedSettings() },
                setPreference: { key, value in _ = SyncedPreferencesStore.shared.set(value, forKey: key) },
                defaults: .standard
            )
        }
    }

    /// What Settings shows. The method, the ParentLocker address and the due
    /// time as the shared row holds them, which is what the roll, the sync,
    /// the reminder, MCP and the assistants read; this device's preferences
    /// only before there is a row. The email's own fields as this device's
    /// preferences hold them, which the notebook's email is written from; in
    /// the Sample Class as its row holds them, since nothing there writes the
    /// preferences.
    static func shownSettings(
        row: AttendanceEmailLog.Settings?, preferences: AttendanceEmailLog.Settings, isSampleClass: Bool
    ) -> AttendanceEmailLog.Settings {
        guard let row else { return preferences }
        var shown = isSampleClass ? row : preferences
        shown.sendMethod = row.sendMethod
        shown.parentLockerSite = row.parentLockerSite
        shown.deadlineMinutes = row.deadlineMinutes
        return shown
    }

    /// Settings' write: `edit`'s fields, and only those, go onto the shared
    /// row as it stands, saved, then into the guide's preferences. A device
    /// whose preferences are behind the share (iCloud hasn't caught up)
    /// changes only what was just changed there, so a new due time keeps the
    /// class's method. With no row yet, this device's settings go in whole,
    /// with the edit.
    /// - Only the lead guide's devices write the row.
    /// - During a first download the share's row may be on its way, so the
    ///   row's write is put off (`AttendanceSettingsPendingWrite`). A write
    ///   put off earlier goes in with the next one, if the row hasn't changed
    ///   since.
    /// - The Sample Class changes its own row only: never the preferences or
    ///   a pending write.
    ///
    /// Returns whether the row was written and saved.
    @discardableResult
    static func shareEdit(
        _ edit: AttendanceSettingsEdit,
        in context: NSManagedObjectContext,
        isSampleClass: Bool,
        device: DeviceSettings = .thisDevice,
        firstDownloadPending: Bool = FirstDownloadGate.isPending()
    ) -> Bool {
        guard !edit.isEmpty else { return false }
        guard !isSampleClass else { return writeEdit(edit, in: context, device: device) }
        defer {
            for (key, value) in edit.preferenceValues { device.setPreference(key, value) }
        }
        guard CDClassroomMembership.currentRole(in: context) == .leadGuide else { return false }
        let row = AttendanceSettingsPendingWrite.rowStamp(in: context)
        let earlier = AttendanceSettingsPendingWrite.load(from: device.defaults)
            .flatMap { $0.row == row ? $0.edit : nil }
        let owed = (earlier ?? AttendanceSettingsEdit()).merged(with: edit)
        guard !firstDownloadPending else {
            AttendanceSettingsPendingWrite(edit: owed, row: row).save(to: device.defaults)
            return false
        }
        AttendanceSettingsPendingWrite.clear(in: device.defaults)
        return writeEdit(owed, in: context, device: device)
    }

    /// Settings opening: the one write this device still owes the share (an
    /// edit put off during a first download) goes in, but only onto the row
    /// it was made against, unchanged since. Otherwise that row's values
    /// stand and the edit is dropped. Nothing else is written here: this
    /// device's preferences may be behind the share, and copying them over it
    /// switched the whole class back to email. Never in the Sample Class.
    /// Returns whether the row was written and saved.
    @discardableResult
    static func writePendingEdit(
        in context: NSManagedObjectContext,
        isSampleClass: Bool,
        device: DeviceSettings = .thisDevice,
        firstDownloadPending: Bool = FirstDownloadGate.isPending()
    ) -> Bool {
        guard !isSampleClass, !firstDownloadPending,
              let pending = AttendanceSettingsPendingWrite.load(from: device.defaults) else { return false }
        AttendanceSettingsPendingWrite.clear(in: device.defaults)
        guard CDClassroomMembership.currentRole(in: context) == .leadGuide,
              pending.row == AttendanceSettingsPendingWrite.rowStamp(in: context) else { return false }
        return writeEdit(pending.edit, in: context, device: device)
    }

    /// `edit` onto the newest row, or with none yet onto this device's
    /// settings, saved.
    private static func writeEdit(
        _ edit: AttendanceSettingsEdit, in context: NSManagedObjectContext, device: DeviceSettings
    ) -> Bool {
        let preferences = device.stored()
        let base = AttendanceEmailLog.settings(in: context) ?? preferences
        let role = CDClassroomMembership.currentRole(in: context)
        let settings = edit.applied(to: base, emailOn: preferences.isEnabled)
        guard AttendanceEmailLog.saveSettings(settings, role: role, in: context) else { return false }
        return context.safeSave()
    }

    /// Builds the body using the teacher's stored name-order and grouping preferences.
    public static func makeBody(
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
        leftEarly: [AttendanceEmailStudent] = [],
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        AttendanceEmailReport.makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            leftEarly: leftEarly,
            date: date,
            calendar: calendar,
            nameOrder: storedNameOrder(),
            groupByLevel: storedGroupByLevel()
        )
    }

    #if os(iOS)
    /// Creates a prefilled mail composer using current preferences.
    /// - Important: Check `AttendanceEmail.isAvailable` before
    ///   presenting. If unavailable, consider using
    ///   `mailtoURLForCurrentPrefs(...)` as a fallback.
    public static func composerForCurrentPrefs(
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
        leftEarly: [AttendanceEmailStudent] = [],
        date: Date = Date(),
        calendar: Calendar = .current,
        onComplete: @escaping (MFMailComposeResult, Error?) -> Void
    ) -> MailComposerView {
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            leftEarly: leftEarly,
            date: date,
            calendar: calendar
        )
        let to = parseRecipients(from: storedToAddress())
        let from = storedFromAddress()
        return MailComposerView(
            toRecipients: to,
            subject: subject,
            body: body,
            preferredSender: from,
            onComplete: onComplete
        )
    }
    #endif

    #if os(macOS)
    public static func sendUsingMailAppForCurrentPrefs(
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
        leftEarly: [AttendanceEmailStudent] = [],
        date: Date = Date(),
        calendar: Calendar = .current,
        completion: @escaping (Bool) -> Void
    ) {
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            leftEarly: leftEarly,
            date: date,
            calendar: calendar
        )
        MacOSMailSender.send(
            to: storedToAddress(),
            subject: subject,
            body: body,
            completion: completion
        )
    }

    #endif
}
