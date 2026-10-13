// AttendanceSettingsEdit.swift
// What Settings › Messages › Attendance to the School writes into the shared
// settings row, and when (bug hunt 2026-10-13 afternoon, H1 and L3): one
// edit's fields and nothing else, a write this device had to put off, and
// what was typed and not yet written. Notebook only.

import CoreData
import Foundation

/// One change made in Settings: the fields it sets, and nothing else.
/// Settings writes an edit onto the shared row as it stands
/// (`AttendanceEmail.shareEdit`), so a device whose preferences are behind
/// the share changes only what was just changed there.
struct AttendanceSettingsEdit: Equatable, Sendable {
    var sendMethod: AttendanceSendMethod?
    /// The ParentLocker host, as `AttendanceEmailLog.parentLockerHost` reads what was typed.
    var parentLockerSite: String?
    var deadlineMinutes: Int?
    var isEnabled: Bool?
    /// The email's recipients as typed: the preference keeps them so, and
    /// the row as `AttendanceEmail.sharedAddressLine` writes them.
    var toAddresses: String?
    var nameOrder: AttendanceEmailNameOrder?
    var groupByLevel: Bool?

    var isEmpty: Bool { self == Self() }

    /// This edit with `later`'s fields on top.
    func merged(with later: Self) -> Self {
        Self(
            sendMethod: later.sendMethod ?? sendMethod,
            parentLockerSite: later.parentLockerSite ?? parentLockerSite,
            deadlineMinutes: later.deadlineMinutes ?? deadlineMinutes,
            isEnabled: later.isEnabled ?? isEnabled,
            toAddresses: later.toAddresses ?? toAddresses,
            nameOrder: later.nameOrder ?? nameOrder,
            groupByLevel: later.groupByLevel ?? groupByLevel
        )
    }

    /// `base` with these fields set. The row holds the email off while
    /// ParentLocker is picked (`Settings.shared`), so picking the email again
    /// turns it on as the guide's own switch says (`emailOn`).
    func applied(to base: AttendanceEmailLog.Settings, emailOn: Bool) -> AttendanceEmailLog.Settings {
        var settings = base
        if let sendMethod {
            if sendMethod == .email, base.sendMethod != .email { settings.isEnabled = emailOn }
            settings.sendMethod = sendMethod
        }
        if let parentLockerSite { settings.parentLockerSite = parentLockerSite }
        if let deadlineMinutes { settings.deadlineMinutes = deadlineMinutes }
        if let isEnabled { settings.isEnabled = isEnabled }
        if let toAddresses { settings.toAddresses = AttendanceEmail.sharedAddressLine(toAddresses) }
        if let nameOrder { settings.nameOrder = nameOrder }
        if let groupByLevel { settings.groupByLevel = groupByLevel }
        return settings
    }

    /// The guide's preferences these fields are copied into, by key.
    var preferenceValues: [String: Any] {
        var values: [String: Any] = [:]
        values[AttendanceEmailPrefs.sendMethodKey] = sendMethod?.rawValue
        values[AttendanceEmailPrefs.parentLockerSiteKey] = parentLockerSite
        values[AttendanceEmailPrefs.deadlineKey] = deadlineMinutes
        values[AttendanceEmailPrefs.enabledKey] = isEnabled
        values[AttendanceEmailPrefs.toKey] = toAddresses
        values[AttendanceEmailPrefs.nameOrderKey] = nameOrder?.rawValue
        values[AttendanceEmailPrefs.groupByLevelKey] = groupByLevel
        return values
    }
}

extension AttendanceSettingsEdit {
    /// An edit read back from its `preferenceValues` (a pending write as kept).
    init(preferenceValues values: [String: Any]) {
        self.init(
            sendMethod: (values[AttendanceEmailPrefs.sendMethodKey] as? String)
                .flatMap(AttendanceSendMethod.init(rawValue:)),
            parentLockerSite: values[AttendanceEmailPrefs.parentLockerSiteKey] as? String,
            deadlineMinutes: values[AttendanceEmailPrefs.deadlineKey] as? Int,
            isEnabled: values[AttendanceEmailPrefs.enabledKey] as? Bool,
            toAddresses: values[AttendanceEmailPrefs.toKey] as? String,
            nameOrder: (values[AttendanceEmailPrefs.nameOrderKey] as? String)
                .flatMap(AttendanceEmailNameOrder.init(rawValue:)),
            groupByLevel: values[AttendanceEmailPrefs.groupByLevelKey] as? Bool
        )
    }
}

/// A Settings edit this device couldn't put into the share when it was made:
/// a first download was under way, and the share's row may have been on its
/// way. Kept on this device only (never synced or backed up), with the shared
/// row as it stood then. Settings writes it when it next opens, but only onto
/// that same row, unchanged since; a row that has changed (another device's
/// edit, or the share's row arriving on a new device) wins, and the edit is
/// dropped (`AttendanceEmail.writePendingEdit`).
struct AttendanceSettingsPendingWrite: Equatable {

    /// Which settings row the share held, and when it last changed.
    struct RowStamp: Equatable, Sendable {
        let id: UUID?
        let modifiedAt: Date?
    }

    var edit: AttendanceSettingsEdit
    /// The shared row when the write was put off; nil when there was none.
    var row: RowStamp?

    /// Per CloudKit environment, as the store it waits for is.
    static var key: String { CloudKitEnvironment.scoped("AttendanceEmail.pendingSharedWrite") }

    /// The newest settings row's stamp (the one every reader takes); nil with none.
    static func rowStamp(in context: NSManagedObjectContext) -> RowStamp? {
        let request = CDFetchRequest(CDAttendanceEmailSettings.self)
        request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        request.fetchLimit = 1
        return context.safeFetchFirst(request).map { RowStamp(id: $0.id, modifiedAt: $0.modifiedAt) }
    }

    static func load(from defaults: UserDefaults) -> Self? {
        guard let kept = defaults.dictionary(forKey: key),
              let fields = kept[Field.fields] as? [String: Any] else { return nil }
        let edit = AttendanceSettingsEdit(preferenceValues: fields)
        guard !edit.isEmpty else { return nil }
        guard kept[Field.hadRow] as? Bool == true else { return Self(edit: edit, row: nil) }
        let row = RowStamp(
            id: (kept[Field.rowID] as? String).flatMap(UUID.init(uuidString:)),
            // Kept as the interval itself, so the comparison is exact.
            modifiedAt: (kept[Field.rowModifiedAt] as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
        )
        return Self(edit: edit, row: row)
    }

    func save(to defaults: UserDefaults) {
        var kept: [String: Any] = [Field.fields: edit.preferenceValues, Field.hadRow: row != nil]
        kept[Field.rowID] = row?.id?.uuidString
        kept[Field.rowModifiedAt] = row?.modifiedAt?.timeIntervalSinceReferenceDate
        defaults.set(kept, forKey: Self.key)
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }

    private enum Field {
        static let fields = "fields"
        static let hadRow = "hadRow"
        static let rowID = "rowID"
        static let rowModifiedAt = "rowModifiedAt"
    }
}

/// What Settings has been given and hasn't written yet. Only these, at the
/// moments below, and the controls' own actions ever write: never a value
/// that merely changed on screen, so a change synced in while Settings is
/// open is never taken for an edit (H1).
struct AttendanceSettingsDrafts: Equatable {
    /// The ParentLocker address as typed. It goes in on Return, before the
    /// sign-in sheet opens, or as Settings closes; never after a pause, since
    /// each half-typed host signed this device out (L3).
    var site: String?
    /// The email's addresses and the due time, waiting for typing to pause:
    /// each write is a CloudKit upload.
    var paused = AttendanceSettingsEdit()

    /// The typed address as an edit, unless it reads as the address `shown`;
    /// clears it.
    mutating func takeSite(shown: String) -> AttendanceSettingsEdit {
        let typed = site
        site = nil
        guard let typed else { return AttendanceSettingsEdit() }
        let host = AttendanceEmailLog.parentLockerHost(typed)
        return host == shown ? AttendanceSettingsEdit() : AttendanceSettingsEdit(parentLockerSite: host)
    }

    /// The pause's write: what waited for it, never the address.
    mutating func takePaused() -> AttendanceSettingsEdit {
        let edit = paused
        paused = AttendanceSettingsEdit()
        return edit
    }

    /// Settings closing: everything not yet written.
    mutating func takeAll(shownSite: String) -> AttendanceSettingsEdit {
        takePaused().merged(with: takeSite(shown: shownSite))
    }
}
