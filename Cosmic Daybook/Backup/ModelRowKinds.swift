// ModelRowKinds.swift
// The entity types backed up through `ModelRow`, one short spec each. The old
// DTO names are aliases, so the payload, the entity table and the preview are
// unchanged. Every other attribute fact comes from the model (see ModelRow.swift).
//
// `filling` lists the optional attributes the export writes "now" (dates), a new
// id or `[]` for when nil — what the hand-written transformers did, and what
// older builds need to decode a row. Everything not listed follows the model:
// a non-optional attribute is required, an optional one is left out when nil.

import Foundation

public typealias LessonRecallCheckDTO = ModelRow<LessonRecallCheckBackupRow>

public enum LessonRecallCheckBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "LessonRecallCheck",
        filling: ["createdAt"]
    )
}

public typealias MeetingTemplateDTO = ModelRow<MeetingTemplateBackupRow>

public enum MeetingTemplateBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "MeetingTemplate",
        filling: ["createdAt"]
    )
}

public typealias TrackDTO = ModelRow<TrackBackupRow>

public enum TrackBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Track",
        filling: ["createdAt"]
    )
}

public typealias ScheduleDTO = ModelRow<ScheduleBackupRow>

public enum ScheduleBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Schedule",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias GoingOutDTO = ModelRow<GoingOutBackupRow>

public enum GoingOutBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "GoingOut",
        filling: ["createdAt", "modifiedAt", "studentIDs"]
    )
}

public typealias ClassroomJobDTO = ModelRow<ClassroomJobBackupRow>

public enum ClassroomJobBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "ClassroomJob",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias CalendarNoteDTO = ModelRow<CalendarNoteBackupRow>

public enum CalendarNoteBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "CalendarNote",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias ClassroomMembershipDTO = ModelRow<ClassroomMembershipBackupRow>

public enum ClassroomMembershipBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "ClassroomMembership",
        filling: ["joinedAt", "modifiedAt"]
    )
}

public typealias StudentFocusItemDTO = ModelRow<StudentFocusItemBackupRow>

public enum StudentFocusItemBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "StudentFocusItem",
        filling: ["createdAt"]
    )
}

public typealias DayPadDTO = ModelRow<DayPadBackupRow>

public enum DayPadBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "DayPad",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias YearPlanEntryDTO = ModelRow<YearPlanEntryBackupRow>

public enum YearPlanEntryBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "YearPlanEntry",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias LessonSequenceSettingsDTO = ModelRow<LessonSequenceSettingsBackupRow>

public enum LessonSequenceSettingsBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "LessonSequenceSettings",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias BookClubSessionDTO = ModelRow<BookClubSessionBackupRow>

public enum BookClubSessionBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "BookClubSession",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias GuardianDTO = ModelRow<GuardianBackupRow>

public enum GuardianBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Guardian",
        filling: ["createdAt"]
    )
}

public typealias ParentCommunicationDTO = ModelRow<ParentCommunicationBackupRow>

public enum ParentCommunicationBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "ParentCommunication",
        filling: ["createdAt"]
    )
}

public typealias AlbumBookmarkDTO = ModelRow<AlbumBookmarkBackupRow>

public enum AlbumBookmarkBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "AlbumBookmark",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias AlbumPageNoteDTO = ModelRow<AlbumPageNoteBackupRow>

public enum AlbumPageNoteBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "AlbumPageNote",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias AlbumRecentVisitDTO = ModelRow<AlbumRecentVisitBackupRow>

public enum AlbumRecentVisitBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "AlbumRecentVisit",
        filling: ["visitedAt", "modifiedAt"]
    )
}

public typealias AlbumReadingPositionDTO = ModelRow<AlbumReadingPositionBackupRow>

public enum AlbumReadingPositionBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "AlbumReadingPosition",
        filling: ["modifiedAt"]
    )
}

public typealias AttendanceDayLockDTO = ModelRow<AttendanceDayLockBackupRow>

/// A locked attendance day (format v30+). Nothing older reads it, so nothing
/// needs filling.
public enum AttendanceDayLockBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec("AttendanceDayLock")
}

public typealias SupplyTransactionDTO = ModelRow<SupplyTransactionBackupRow>

/// One change to a supply's stock (format v31+). `supplyID` is an attribute,
/// so the row carries it as is; the restore re-links `supply` from it. No
/// date is made up for a transaction without one.
public enum SupplyTransactionBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "SupplyTransaction",
        parents: [ParentLink(key: "supplyID", relationship: "supply")]
    )
}

public typealias OrderItemDTO = ModelRow<OrderItemBackupRow>

public enum OrderItemBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "OrderItem",
        filling: ["createdAt", "modifiedAt"]
    )
}

public typealias ProposedSolutionDTO = ModelRow<ProposedSolutionBackupRow>

public enum ProposedSolutionBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "ProposedSolution",
        filling: ["createdAt"],
        parentIDs: ["topicID": "topic"],
        parents: [ParentLink(key: "topicID", relationship: "topic")],
        dropsRecordsWithoutID: true
    )
}

public typealias WorkStepDTO = ModelRow<WorkStepBackupRow>

public enum WorkStepBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "WorkStep",
        filling: ["createdAt"],
        parentIDs: ["workID": "work"],
        parents: [ParentLink(key: "workID", relationship: "work")]
    )
}

public typealias SampleWorkStepDTO = ModelRow<SampleWorkStepBackupRow>

public enum SampleWorkStepBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "SampleWorkStep",
        filling: ["createdAt"],
        parentIDs: ["sampleWorkID": "sampleWork"],
        parents: [ParentLink(key: "sampleWorkID", relationship: "sampleWork")]
    )
}

public typealias TrackStepDTO = ModelRow<TrackStepBackupRow>

public enum TrackStepBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "TrackStep",
        filling: ["createdAt"],
        parentIDs: ["trackID": "track"],
        parents: [ParentLink(key: "trackID", relationship: "track")]
    )
}

public typealias TodoSubtaskDTO = ModelRow<TodoSubtaskBackupRow>

public enum TodoSubtaskBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "TodoSubtask",
        filling: ["createdAt"],
        parentIDs: ["todoID": "todo"],
        parents: [ParentLink(key: "todoID", relationship: "todo")]
    )
}

public typealias LessonAttachmentDTO = ModelRow<LessonAttachmentBackupRow>

public enum LessonAttachmentBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "LessonAttachment",
        filling: ["attachedAt"],
        // Device-local blobs, excluded by design.
        omitting: ["fileBookmark", "thumbnailData"],
        parentIDs: ["lessonID": "lesson"],
        parents: [ParentLink(key: "lessonID", relationship: "lesson")]
    )
}

public typealias NoteStudentLinkDTO = ModelRow<NoteStudentLinkBackupRow>

public enum NoteStudentLinkBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "NoteStudentLink",
        parents: [ParentLink(key: "noteID", relationship: "note")]
    )
}

public typealias JobAssignmentDTO = ModelRow<JobAssignmentBackupRow>

public enum JobAssignmentBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "JobAssignment",
        filling: ["createdAt", "modifiedAt", "weekStartDate"],
        parents: [ParentLink(key: "jobID", relationship: "job")]
    )
}

public typealias BookClubMeetingDTO = ModelRow<BookClubMeetingBackupRow>

public enum BookClubMeetingBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "BookClubMeeting",
        filling: ["createdAt", "modifiedAt"],
        parents: [ParentLink(key: "sessionID", relationship: "session")]
    )
}

public typealias StudentTrackEnrollmentDTO = ModelRow<StudentTrackEnrollmentBackupRow>

public enum StudentTrackEnrollmentBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "StudentTrackEnrollment",
        filling: ["createdAt"],
        // A missing track clears it. The student is `studentID` alone since
        // schema 9 (no relationship to set).
        parents: [
            ParentLink(key: "trackID", relationship: "track", missing: .clearWhenNotFound)
        ]
    )
}

public typealias MeetingWorkReviewDTO = ModelRow<MeetingWorkReviewBackupRow>

public enum MeetingWorkReviewBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "MeetingWorkReview",
        filling: ["createdAt"],
        parents: [ParentLink(key: "meetingID", relationship: "meeting", missing: .alwaysSet)]
    )
}
