// ModelRowKinds+Calendar.swift
// The backup rows of the school calendar and the day's records (days off,
// extra school days, meetings, attendance, the device's calendar events and
// booked meetings), as their hand-written DTOs wrote and restored them until
// "Simplify round two", Phase 7 (see ModelRowKinds.swift).

import CoreData
import Foundation

public typealias NonSchoolDayDTO = ModelRow<NonSchoolDayBackupRow>
public typealias SchoolDayOverrideDTO = ModelRow<SchoolDayOverrideBackupRow>
public typealias StudentMeetingDTO = ModelRow<StudentMeetingBackupRow>
public typealias AttendanceRecordDTO = ModelRow<AttendanceRecordBackupRow>
public typealias CalendarEventDTO = ModelRow<CalendarEventBackupRow>
public typealias ScheduledMeetingDTO = ModelRow<ScheduledMeetingBackupRow>

/// A day off school; a record with no `id` or no date isn't backed up. A
/// restore that brings any back announces it
/// (`BackupRestoreRun.notifySchoolDayDataChanged`).
public enum NonSchoolDayBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "NonSchoolDay",
        requiring: ["date"],
        dropsRecordsWithoutID: true
    )
}

/// A weekend day made a school day; a record with no `id` or no date isn't
/// backed up. A restore that brings any back announces it, as for days off.
public enum SchoolDayOverrideBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "SchoolDayOverride",
        requiring: ["date"],
        dropsRecordsWithoutID: true
    )
}

/// A child's meeting with the guide; a record with no `id`, no date or a
/// `studentID` that isn't an id isn't backed up. The student id restores
/// upper-cased.
public enum StudentMeetingBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "StudentMeeting",
        uuidStrings: ["studentID"],
        requiring: ["date", "studentID"],
        dropsRecordsWithoutID: true
    )
}

/// One child's attendance on one day; a record with no `id`, no date or a
/// `studentID` that isn't an id isn't backed up. The student id restores
/// upper-cased.
///
/// - `status` carries `statusRaw` read through the typed status (an unknown
///   raw goes out as unmarked); one that isn't a status restores as
///   unmarked. It is set as stored, so it leaves the absence reason alone.
/// - `absenceReason` carries `absenceReasonRaw` as stored, so Close Arrival's
///   "closeArrival" (no typed case) comes back as itself; "none" goes out as
///   no key, and a row without one restores as none.
/// - Who marked it, the note and the times are cleared when a row lacks
///   them; a restore from a format older than one of them keeps the
///   record's own (`BackupFieldsAddedLater`).
public enum AttendanceRecordBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "AttendanceRecord",
        omitting: ["statusRaw", "absenceReasonRaw"],
        uuidStrings: ["studentID"],
        requiring: ["date", "studentID"],
        computed: [
            .raw(
                "status", attribute: "statusRaw", of: CDAttendanceRecord.self,
                read: { $0.status }, fallback: AttendanceStatus.unmarked
            ),
            .computed(
                "absenceReason", .string, of: CDAttendanceRecord.self,
                read: { record in
                    record.absenceReasonRaw == AbsenceReason.none.rawValue ? nil : .string(record.absenceReasonRaw)
                },
                write: { record, value, _ in
                    guard case .string(let raw)? = value else {
                        record.absenceReasonRaw = AbsenceReason.none.rawValue
                        return
                    }
                    record.absenceReasonRaw = raw
                }
            )
        ],
        dropsRecordsWithoutID: true
    )
}

/// A copy of an event in the device's Apple Calendar: carried, never
/// restored (`BackupEntityRegistry.keptOnRestoreEntityNames`; the next sync
/// rebuilds them). A record without an `id` or a start or end goes out with
/// a new id and dated now. The EventKit ids and sync date are this device's
/// own, so they aren't backed up.
public enum CalendarEventBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "CalendarEvent",
        filling: ["startDate", "endDate"],
        omitting: ["eventKitEventID", "eventKitCalendarID", "lastSyncedAt"]
    )
}

/// A meeting booked with a child (format v12+). A row whose `studentID`
/// isn't an id is passed over on restore; one that is restores it
/// upper-cased (it goes out as stored). `participantIDsData` carries the
/// participant blob as it is stored. A row without `isGroupMeeting` restores
/// as not a group meeting. A record without a date goes out dated now, as
/// one without an `id` gets a new one.
public enum ScheduledMeetingBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "ScheduledMeeting",
        filling: ["date", "createdAt"],
        renaming: ["participantIDsData": "_participantIDsData"],
        computed: [
            .computed(
                "studentID", .string, of: CDScheduledMeeting.self, required: true,
                read: { .string($0.studentID) },
                write: { meeting, value, _ in
                    guard case .string(let text)? = value, let id = UUID(uuidString: text) else { return }
                    meeting.studentID = id.uuidString
                }
            ),
            .computed(
                "isGroupMeeting", .bool, of: CDScheduledMeeting.self,
                read: { .bool($0.isGroupMeeting) },
                write: { meeting, value, _ in meeting.isGroupMeeting = value == .bool(true) }
            )
        ],
        restoresRow: { values in
            if case .string(let text)? = values["studentID"] { UUID(uuidString: text) != nil } else { false }
        }
    )
}
