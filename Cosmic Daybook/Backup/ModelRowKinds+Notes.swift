// ModelRowKinds+Notes.swift
// The note's backup row, as the hand-written NoteDTO wrote and restored it
// until "Simplify round two", Phase 7 (see ModelRowKinds.swift).

import CoreData
import Foundation
import OSLog

public typealias NoteDTO = ModelRow<NoteBackupRow>

/// An observation or other note; a record with no `id` isn't backed up.
///
/// - `scope` carries the typed scope as a JSON string ("{}" when it won't
///   encode); a string that won't decode leaves the record's scope. Setting
///   it sets the search columns, which aren't backed up.
/// - `tags` and `needsFollowUp` go out only when there are some or it's on,
///   and restore as none and off when a row lacks them.
/// - `lessonID` and `attendanceRecordID` are string ids carried as UUIDs. A
///   row without the attendance record leaves the record's own, as the old
///   end-of-restore relink did; a row without the lesson clears it.
/// - `includeInReport` (v19) leaves the record's own when a row lacks it.
/// - The parents in the private store (work, assignment, check-in,
///   completion, meeting, project session, issue) restore after them, so
///   each is re-linked once every type is in (`BackupRestoreRun.relinkNotes`):
///   to the record found by the row's id, or to nothing. A row without one
///   leaves that link as it is.
///
/// The old row also read `reminderID` and `practiceSessionID` (retired types,
/// never written or restored); they're no longer read at all. The legacy
/// category isn't backed up.
public enum NoteBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Note",
        filling: ["createdAt", "updatedAt"],
        omitting: ["categoryRaw", "scopeBlob", "scopeIsAll", "searchIndexStudentID", "transitionPlanID"],
        addedLater: ["includeInReport", "attendanceRecordID"],
        uuidStrings: ["lessonID", "attendanceRecordID"],
        computed: [
            .computed(
                "scope", .string, of: CDNote.self, required: true,
                read: { note in
                    do {
                        let data = try JSONEncoder().encode(note.scope)
                        return .string(String(data: data, encoding: .utf8) ?? "{}")
                    } catch {
                        let desc = error.localizedDescription
                        Logger.backup.warning("Failed to encode note scope: \(desc, privacy: .public)")
                        return .string("{}")
                    }
                },
                write: { note, value, _ in
                    guard case .string(let text)? = value else { return }
                    do {
                        note.scope = try JSONDecoder().decode(NoteScope.self, from: Data(text.utf8))
                    } catch {
                        let desc = error.localizedDescription
                        Logger.backup.warning("Failed to decode note scope: \(desc, privacy: .public)")
                    }
                }
            ),
            .computed(
                "tags", .strings, of: CDNote.self,
                read: { note in note.tagsArray.isEmpty ? nil : .strings(note.tagsArray) },
                write: { note, value, _ in
                    guard case .strings(let tags)? = value else {
                        note.tagsArray = []
                        return
                    }
                    note.tagsArray = tags
                }
            ),
            .computed(
                "needsFollowUp", .bool, of: CDNote.self,
                read: { $0.needsFollowUp ? .bool(true) : nil },
                write: { note, value, _ in note.needsFollowUp = value == .bool(true) }
            )
        ],
        parentIDs: Dictionary(uniqueKeysWithValues: NoteParents.links.map { ($0.key, $0.relationship) }),
        parents: NoteParents.links.map { ParentLink(key: $0.key, relationship: $0.relationship, deferred: true) },
        dropsRecordsWithoutID: true
    )
}

/// A note's parents in the private store, by row key, in the order the old
/// relink set them.
nonisolated private enum NoteParents {
    static let links: [(key: String, relationship: String)] = [
        ("workID", "work"),
        ("lessonAssignmentID", "lessonAssignment"),
        ("workCheckInID", "workCheckIn"),
        ("workCompletionRecordID", "workCompletionRecord"),
        ("studentMeetingID", "studentMeeting"),
        ("projectSessionID", "projectSession"),
        ("issueID", "issue")
    ]
}
