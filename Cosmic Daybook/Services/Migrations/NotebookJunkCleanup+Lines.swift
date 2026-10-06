//
//  NotebookJunkCleanup+Lines.swift
//  Cosmic Daybook
//
//  The lines Clean Up Leftovers lists before and after a run
//  (`NotebookCleanupSheet`), kept apart from the sweep itself.
//

import Foundation

nonisolated extension NotebookJunkCleanup.Counts {

    /// One line per kind, in the guide's words, for the sheet and the log; kinds with
    /// nothing are left out.
    var lines: [String] {
        [
            Self.line(orphanTrackSteps, "track step with no track", "track steps with no track"),
            Self.line(
                blankPresentations,
                "lesson given with no child or lesson", "lessons given with no child or lesson"
            ),
            Self.line(
                presentationsOfDeletedLessons,
                "lesson given whose lesson was deleted", "lessons given whose lesson was deleted"
            ),
            Self.line(
                detachedWorkParticipants,
                "child on work that no longer exists", "children on work that no longer exists"
            ),
            Self.line(blankAttendance, "empty attendance entry", "empty attendance entries"),
            Self.line(
                departedPlansSkipped,
                "planned lesson for a child who's left, marked skipped",
                "planned lessons for children who've left, marked skipped"
            ),
            Self.line(
                enrollmentsRelinked,
                "old track enrollment linked to its track", "old track enrollments linked to their tracks"
            ),
            Self.line(enrollmentsRemoved, "old track enrollment removed", "old track enrollments removed"),
            Self.line(duplicateReminders, "duplicate reminder", "duplicate reminders"),
            Self.line(emptyNotes, "empty note", "empty notes"),
            Self.line(documentsWithoutFile, "document with no file", "documents with no file"),
            Self.line(emptyTracks, "empty track", "empty tracks"),
            Self.line(orphanWorkSteps + orphanSampleWorkSteps, "work step with no work", "work steps with no work"),
            Self.line(
                completionRecordsOfDeletedWork,
                "completed-work entry for work that was deleted",
                "completed-work entries for work that was deleted"
            ),
            Self.line(
                completionNotesKept,
                "note written on those entries kept in the child's notes",
                "notes written on those entries kept in the children's notes"
            )
        ]
        .compactMap { $0 }
    }

    /// "1 empty note", "3 empty notes", or nil for none.
    private static func line(_ count: Int, _ one: String, _ many: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count.formatted()) \(count == 1 ? one : many)"
    }
}
