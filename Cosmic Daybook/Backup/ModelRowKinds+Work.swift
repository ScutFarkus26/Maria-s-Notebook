// ModelRowKinds+Work.swift
// The backup rows of work and what hangs off it (check-ins, the children on
// it, completions), as their hand-written DTOs wrote and restored them until
// "Simplify round two", Phase 7 (see ModelRowKinds.swift). Work steps were
// already table rows (ModelRowKinds.swift).

import CoreData
import Foundation

public typealias WorkModelDTO = ModelRow<WorkModelBackupRow>
public typealias WorkCheckInDTO = ModelRow<WorkCheckInBackupRow>
public typealias WorkParticipantEntityDTO = ModelRow<WorkParticipantEntityBackupRow>
public typealias WorkCompletionRecordDTO = ModelRow<WorkCompletionRecordBackupRow>

/// A piece of work. `statusRaw` goes out as stored and restores folded with
/// the row's `completionOutcomeRaw` (`WorkStatusMigration.mergedStatus`: an
/// old backup's "complete" + outcome comes back as the one merged status, and
/// a raw no build has written as active); the outcome itself restores as it
/// is. A record without an `id` goes out with a new one, as one without a
/// created or assigned date goes out dated now. The two pre-migration
/// `legacy…` ids aren't backed up.
public enum WorkModelBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "WorkModel",
        filling: ["createdAt", "assignedAt"],
        omitting: ["legacyContractID", "legacyStudentLessonID"],
        computed: [
            .computed(
                "statusRaw", .string, of: CDWorkModel.self, required: true,
                read: { .string($0.statusRaw) },
                write: { work, value, row in
                    guard case .string(let raw)? = value else { return }
                    var outcome: String?
                    if case .string(let text)? = row["completionOutcomeRaw"] { outcome = text }
                    work.statusRaw = WorkStatusMigration.mergedStatus(statusRaw: raw, outcomeRaw: outcome).rawValue
                }
            )
        ]
    )
}

/// One day's check-in on a piece of work. A row whose `workID` isn't an id is
/// passed over on restore; one that is restores it as stored and files the
/// check-in under that work when it's here (one that isn't leaves the link as
/// it is). A status that isn't one restores as scheduled (it goes out as
/// stored). `studentInitiated` (v19) and `durationMinutes` (schema 23) leave
/// the record's own when a row lacks them; the duration goes out and
/// restores through `durationMinutesValue` (none for zero or less). A record
/// without an `id` goes out with a new one, as one without a date goes out
/// dated now.
public enum WorkCheckInBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "WorkCheckIn",
        filling: ["date"],
        addedLater: ["studentInitiated"],
        computed: [
            .computed(
                "statusRaw", .string, of: CDWorkCheckIn.self, required: true,
                read: { .string($0.statusRaw) },
                write: { checkIn, value, _ in
                    guard case .string(let raw)? = value else { return }
                    checkIn.statusRaw = (WorkCheckInStatus(rawValue: raw) ?? .scheduled).rawValue
                }
            ),
            .computed(
                "durationMinutes", .int, of: CDWorkCheckIn.self, kept: true,
                read: { $0.durationMinutesValue.map(ModelValue.int) },
                write: { checkIn, value, _ in
                    if case .int(let minutes)? = value { checkIn.durationMinutesValue = minutes }
                }
            )
        ],
        parents: [ParentLink(key: "workID", relationship: "work")],
        restoresRow: { values in
            if case .string(let text)? = values["workID"] { UUID(uuidString: text) != nil } else { false }
        }
    )
}

/// One child on a piece of work. A row whose `studentID` isn't an id is
/// passed over on restore (one that is restores it as stored). `workID`
/// carries the work's id; a work that can't be found, or a row without one,
/// leaves the link as it is. A record without an `id` goes out with a new
/// one.
public enum WorkParticipantEntityBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "WorkParticipantEntity",
        parentIDs: ["workID": "work"],
        parents: [ParentLink(key: "workID", relationship: "work")],
        restoresRow: { values in
            if case .string(let text)? = values["studentID"] { UUID(uuidString: text) != nil } else { false }
        }
    )
}

/// One child's completion of a piece of work; a record with no `id`, no
/// date, or a `workID` or `studentID` that isn't an id isn't backed up. Both
/// ids restore upper-cased. It names its work by id only: there's no link to
/// re-make.
public enum WorkCompletionRecordBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "WorkCompletionRecord",
        uuidStrings: ["workID", "studentID"],
        requiring: ["completedAt", "workID", "studentID"],
        dropsRecordsWithoutID: true
    )
}
