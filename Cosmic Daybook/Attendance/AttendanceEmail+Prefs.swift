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
    /// reads as on until turned off, as the settings screen shows it.
    static func storedSettings(from store: SyncedPreferencesStore = .shared) -> AttendanceEmailLog.Settings {
        AttendanceEmailLog.Settings(
            isEnabled: store.get(key: AttendanceEmailPrefs.enabledKey) as? Bool ?? true,
            toAddresses: store.string(forKey: AttendanceEmailPrefs.toKey)?.trimmed() ?? "",
            nameOrder: store.string(forKey: AttendanceEmailPrefs.nameOrderKey)
                .flatMap(AttendanceEmailNameOrder.init(rawValue:)) ?? .firstLast,
            groupByLevel: store.bool(forKey: AttendanceEmailPrefs.groupByLevelKey),
            deadlineMinutes: store.get(key: AttendanceEmailPrefs.deadlineKey) as? Int
                ?? AttendanceEmailLog.defaultDeadlineMinutes
        )
    }

    /// Copies the guide's settings into the classroom share, so an
    /// assistant's email goes to the same people in the same format. Only on
    /// the lead guide's devices, and not during a first download (the share's
    /// row may be on its way). Returns whether anything changed; the caller
    /// saves.
    @discardableResult
    static func shareSettings(in context: NSManagedObjectContext) -> Bool {
        guard !FirstDownloadGate.isPending() else { return false }
        return AttendanceEmailLog.saveSettings(
            storedSettings(), role: CDClassroomMembership.currentRole(in: context), in: context
        )
    }

    /// Builds the body using the teacher's stored name-order and grouping preferences.
    public static func makeBody(
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        AttendanceEmailReport.makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
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
        date: Date = Date(),
        calendar: Calendar = .current,
        onComplete: @escaping (MFMailComposeResult, Error?) -> Void
    ) -> MailComposerView {
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
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
        date: Date = Date(),
        calendar: Calendar = .current,
        completion: @escaping (Bool) -> Void
    ) {
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
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
