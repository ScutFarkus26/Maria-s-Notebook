// BackupPreviewDigest.swift
// What a restore preview needs from a backup — and nothing more.
//
// The preview used to decode the whole archive into a `BackupPayload` (every
// entry's bytes, then every record as a DTO) and look only at counts and IDs.
// The digest keeps just those: how many rows each entity type decoded to, and
// the IDs the merge analysis checks against the store.
// `BackupImporter.decodePreview` fills it while the archive streams, one row
// at a time, so no entity's records are ever held together.

import Foundation

nonisolated struct BackupPreviewDigest: Sendable, Equatable {

    /// A lesson assignment as the merge analysis sees it.
    struct AssignmentReference: Sendable, Equatable {
        let id: UUID
        let lessonID: String
    }

    /// One entity's rows, gathered as they are decoded.
    struct EntityRows {
        let entityName: String
        fileprivate(set) var count = 0
        fileprivate(set) var ids: [UUID] = []
        fileprivate(set) var assignments: [AssignmentReference] = []

        init(entityName: String) {
            self.entityName = entityName
        }

        /// Counts one decoded row and keeps what the merge analysis needs of it.
        mutating func add(_ row: any Sendable) {
            count += 1
            if let assignment = row as? LessonAssignmentDTO {
                assignments.append(AssignmentReference(id: assignment.id, lessonID: assignment.lessonID))
            } else if let id = BackupPreviewDigest.identified[entityName]?.rowID(row) {
                ids.append(id)
            }
        }
    }

    /// Rows per archive entity name, for the types that decoded.
    private(set) var rowCounts: [String: Int] = [:]
    /// Record IDs, in archive order, for the types the merge analysis checks.
    private(set) var recordIDs: [String: [UUID]] = [:]
    private(set) var lessonAssignments: [AssignmentReference] = []
    /// The deprecated project-template sections. Archives never carry them;
    /// a payload built in memory can.
    private(set) var projectAssignmentTemplateCount = 0
    private(set) var projectTemplateWeekCount = 0
    private(set) var projectWeekRoleAssignmentCount = 0

    init() {}

    /// The digest of a whole payload, for a caller that already holds one.
    init(payload: BackupPayload) {
        for serialization in BackupWriter.entitySerializations {
            let name = serialization.entityName
            rowCounts[name] = serialization.count(payload)
            if let identified = Self.identified[name] {
                recordIDs[name] = identified.payloadIDs(payload)
            }
        }
        lessonAssignments = payload.lessonAssignments.map {
            AssignmentReference(id: $0.id, lessonID: $0.lessonID)
        }
        projectAssignmentTemplateCount = payload.projectAssignmentTemplates.count
        projectTemplateWeekCount = payload.projectTemplateWeeks.count
        projectWeekRoleAssignmentCount = payload.projectWeekRoleAssignments.count
    }

    /// How many rows `entityName` decoded to; 0 when it is absent or was skipped.
    func count(_ entityName: String) -> Int {
        rowCounts[entityName] ?? 0
    }

    /// The IDs of `entityName`'s rows, in archive order, duplicates kept.
    func ids(_ entityName: String) -> [UUID] {
        recordIDs[entityName] ?? []
    }

    /// Keeps an entity whose every row decoded, replacing whatever an earlier
    /// entry of the same name left — as assigning the payload field did.
    mutating func record(_ rows: EntityRows) {
        rowCounts[rows.entityName] = rows.count
        if rows.entityName == "LessonAssignment" {
            lessonAssignments = rows.assignments
        } else if Self.identified[rows.entityName] != nil {
            recordIDs[rows.entityName] = rows.ids
        }
    }

    // MARK: - IDs the merge analysis checks

    /// How to read one merge-checked type's IDs: from one decoded row, and
    /// from a whole payload. Lesson assignments, which also carry their lesson,
    /// are read above.
    private struct Identified: Sendable {
        let rowID: @Sendable (any Sendable) -> UUID?
        let payloadIDs: @Sendable (BackupPayload) -> [UUID]
    }

    private static let identified: [String: Identified] = [
        "Student": Identified(rowID: { ($0 as? StudentDTO)?.id }, payloadIDs: { $0.students.map(\.id) }),
        "Lesson": Identified(rowID: { ($0 as? LessonDTO)?.id }, payloadIDs: { $0.lessons.map(\.id) }),
        "Note": Identified(rowID: { ($0 as? NoteDTO)?.id }, payloadIDs: { $0.notes.map(\.id) }),
        "NonSchoolDay": Identified(
            rowID: { ($0 as? NonSchoolDayDTO)?.id }, payloadIDs: { $0.nonSchoolDays.map(\.id) }
        ),
        "SchoolDayOverride": Identified(
            rowID: { ($0 as? SchoolDayOverrideDTO)?.id }, payloadIDs: { $0.schoolDayOverrides.map(\.id) }
        ),
        "StudentMeeting": Identified(
            rowID: { ($0 as? StudentMeetingDTO)?.id }, payloadIDs: { $0.studentMeetings.map(\.id) }
        ),
        "CommunityTopic": Identified(
            rowID: { ($0 as? CommunityTopicDTO)?.id }, payloadIDs: { $0.communityTopics.map(\.id) }
        ),
        "ProposedSolution": Identified(
            rowID: { ($0 as? ProposedSolutionDTO)?.id }, payloadIDs: { $0.proposedSolutions.map(\.id) }
        ),
        "CommunityAttachment": Identified(
            rowID: { ($0 as? CommunityAttachmentDTO)?.id }, payloadIDs: { $0.communityAttachments.map(\.id) }
        ),
        "AttendanceRecord": Identified(
            rowID: { ($0 as? AttendanceRecordDTO)?.id }, payloadIDs: { $0.attendance.map(\.id) }
        ),
        "WorkCompletionRecord": Identified(
            rowID: { ($0 as? WorkCompletionRecordDTO)?.id }, payloadIDs: { $0.workCompletions.map(\.id) }
        ),
        "Project": Identified(rowID: { ($0 as? ProjectDTO)?.id }, payloadIDs: { $0.projects.map(\.id) }),
        "ProjectSession": Identified(
            rowID: { ($0 as? ProjectSessionDTO)?.id }, payloadIDs: { $0.projectSessions.map(\.id) }
        ),
        "ProjectRole": Identified(
            rowID: { ($0 as? ProjectRoleDTO)?.id }, payloadIDs: { $0.projectRoles.map(\.id) }
        )
    ]
}
