// ModelRowKinds+Issues.swift
// The backup rows of the old schedules' slots, and of classroom issues and
// what was done about them, as their hand-written DTOs wrote and restored them
// until "Simplify round two", Phase 7 (see ModelRowKinds.swift). Schedules
// themselves were already table rows (ModelRowKinds.swift).

import CoreData
import Foundation

public typealias ScheduleSlotDTO = ModelRow<ScheduleSlotBackupRow>
public typealias IssueDTO = ModelRow<IssueBackupRow>
public typealias IssueActionDTO = ModelRow<IssueActionBackupRow>

/// One child's slot in an old schedule. Its weekday goes out through the
/// typed weekday (an unknown raw as Monday) and restores as Monday when it
/// isn't one. `scheduleID` goes out and restores as stored; a slot is filed
/// under that schedule when it's here (one that isn't, or a `scheduleID` that
/// isn't an id, leaves the link as it is). A record without an `id` goes out
/// with a new one, as one without a created or changed date goes out dated now.
public enum ScheduleSlotBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "ScheduleSlot",
        filling: ["createdAt", "modifiedAt"],
        computed: [
            .raw("weekdayRaw", of: CDScheduleSlot.self, read: { $0.weekday }, fallback: Weekday.monday)
        ],
        parents: [ParentLink(key: "scheduleID", relationship: "schedule")]
    )
}

/// Something in the classroom to work through. Its category, priority and
/// status go out through their typed accessors (an unknown raw as Other,
/// Medium and Open) and restore as those when they aren't one. `studentIDs`
/// carries the list kept in `_studentIDsData` (a blob that won't decode goes
/// out as none), restored into the blob itself: the typed setter stamps
/// `updatedAt`, which the row restores as it is. A record without an `id`
/// goes out with a new one, as one without a created, updated or changed date
/// goes out dated now.
public enum IssueBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Issue",
        filling: ["createdAt", "updatedAt", "modifiedAt"],
        omitting: ["_studentIDsData"],
        computed: [
            .raw("categoryRaw", of: CDIssue.self, read: { $0.category }, fallback: IssueCategory.other),
            .raw("priorityRaw", of: CDIssue.self, read: { $0.priority }, fallback: IssuePriority.medium),
            .raw("statusRaw", of: CDIssue.self, read: { $0.status }, fallback: IssueStatus.open),
            .computed(
                "studentIDs", .strings, of: CDIssue.self, required: true,
                read: { .strings($0.studentIDs) },
                write: { issue, value, _ in
                    guard case .strings(let ids)? = value else { return }
                    issue._studentIDsData = CloudKitStringArrayStorage.encode(ids)
                }
            )
        ]
    )
}

/// One thing done about an issue. Its kind goes out through the typed kind
/// (an unknown raw as a note) and restores as a note when it isn't one.
/// `participantStudentIDs` carries the list kept in `_participantIDsData`,
/// restored into the blob itself, as an issue's children are. `issueID` goes
/// out and restores as stored; the action is filed under that issue when it's
/// here (one that isn't, or an `issueID` that isn't an id, leaves the link as
/// it is). A record without an `id` goes out with a new one, as one without a
/// created, updated, changed or action date goes out dated now.
public enum IssueActionBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "IssueAction",
        filling: ["createdAt", "updatedAt", "modifiedAt", "actionDate"],
        omitting: ["_participantIDsData"],
        computed: [
            .raw("actionTypeRaw", of: CDIssueAction.self, read: { $0.actionType }, fallback: IssueActionType.note),
            .computed(
                "participantStudentIDs", .strings, of: CDIssueAction.self, required: true,
                read: { .strings($0.participantStudentIDs) },
                write: { action, value, _ in
                    guard case .strings(let ids)? = value else { return }
                    action._participantIDsData = CloudKitStringArrayStorage.encode(ids)
                }
            )
        ],
        parents: [ParentLink(key: "issueID", relationship: "issue")]
    )
}
