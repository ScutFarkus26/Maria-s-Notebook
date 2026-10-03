import Foundation
import Testing
@testable import CosmicDaybook

/// What Clean Up Leftovers lists before and after a run (`NotebookJunkCleanup.Counts.lines`):
/// everyday words, singular or plural by the count, no "record(s)".
@Suite("Notebook junk cleanup lines")
@MainActor
struct NotebookJunkCleanupLinesTests {

    @Test("The sheet's lines are in everyday words, one or many, and leave out what has none")
    func linesReadPlainly() {
        var counts = NotebookJunkCleanup.Counts()
        #expect(counts.lines.isEmpty)
        counts.blankAttendance = 1
        counts.blankPresentations = 2
        counts.detachedWorkParticipants = 1_204
        counts.orphanWorkSteps = 1
        counts.orphanSampleWorkSteps = 1
        #expect(counts.lines == [
            "2 lessons given with no child or lesson",
            "\(1_204.formatted()) children on work that no longer exists",
            "1 empty attendance entry",
            "2 work steps with no work"
        ])
    }

    @Test("No line says record, row or (s)")
    func noDeveloperWords() {
        var counts = NotebookJunkCleanup.Counts()
        counts.orphanTrackSteps = 2
        counts.blankPresentations = 2
        counts.presentationsOfDeletedLessons = 2
        counts.detachedWorkParticipants = 2
        counts.blankAttendance = 2
        counts.departedPlansSkipped = 2
        counts.enrollmentsRelinked = 2
        counts.enrollmentsRemoved = 2
        counts.duplicateReminders = 2
        counts.emptyNotes = 2
        counts.documentsWithoutFile = 2
        counts.emptyTracks = 2
        counts.orphanWorkSteps = 2
        counts.completionRecordsOfDeletedWork = 2
        #expect(counts.lines.count == 14)
        for line in counts.lines {
            #expect(!line.contains("(s)") && !line.contains("record") && !line.contains(" row"), "\(line)")
        }
    }
}
