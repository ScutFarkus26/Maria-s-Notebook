import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A note's links to the records restored after it (work, assignment,
/// check-in, completion, meeting, project session, issue) are its row spec's
/// deferred parents since "Simplify round two", Phase 7: re-linked once every
/// type is in (`BackupRestoreRun.relinkNotes`), as the hand-written relink
/// did. Each is set to the record found by the row's id, or to nothing; one
/// the row doesn't name is left as it is. The attendance record is a string
/// id the row carries. The spec oracle's golden note names none of these, so
/// they're checked here.
@Suite("Backup: a note's links restored last", .serialized)
@MainActor
struct BackupNoteRelinkTests {

    /// A record of `type` from the fixture.
    private static func any<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) throws -> T {
        try #require(context.safeFetch(CDFetchRequest(type)).first, "the fixture holds a \(type)")
    }

    /// A store holding the field-coverage fixture, its note linked to a
    /// record of every type a note can point at and last edited at `editedAt`.
    private static func linkedFixture(editedAt: Date = Fix1102.at(10)) throws -> (CoreDataStack, CDNote) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: context)
        let note = try any(CDNote.self, in: context)
        note.work = try any(CDWorkModel.self, in: context)
        note.lessonAssignment = try any(CDLessonAssignment.self, in: context)
        note.workCheckIn = try any(CDWorkCheckIn.self, in: context)
        note.workCompletionRecord = try any(CDWorkCompletionRecord.self, in: context)
        note.studentMeeting = try any(CDStudentMeeting.self, in: context)
        note.projectSession = try any(CDProjectSession.self, in: context)
        note.issue = try any(CDIssue.self, in: context)
        note.attendanceRecordID = try any(CDAttendanceRecord.self, in: context).id?.uuidString
        note.updatedAt = editedAt
        #expect(CoreDataTestHelpers.save(context), "Fixture save failed")
        return (stack, note)
    }

    /// The ids `note` links to, by relationship (and the attendance record's).
    private static func links(of note: CDNote) -> [String: String] {
        let targets: [String: NSManagedObject?] = [
            "work": note.work, "lessonAssignment": note.lessonAssignment, "workCheckIn": note.workCheckIn,
            "workCompletionRecord": note.workCompletionRecord, "studentMeeting": note.studentMeeting,
            "projectSession": note.projectSession, "issue": note.issue
        ]
        var links = targets.mapValues { ($0?.value(forKey: "id") as? UUID)?.uuidString ?? "none" }
        links["attendanceRecordID"] = note.attendanceRecordID ?? "none"
        return links
    }

    @Test("Through an archive into an empty notebook, every link comes back")
    func everyLinkComesBack() async throws {
        let (source, note) = try Self.linkedFixture()
        let noteID = try #require(note.id)
        let expected = Self.links(of: note)
        #expect(!expected.values.contains("none"), "the fixture links every one")

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source.viewContext, to: url)
        // Merge into an empty notebook does what Replace would (BackupRoundTripTests).
        let restoredStack = try CoreDataTestHelpers.makeInMemoryStack()
        let restored = restoredStack.viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .merge)

        let restoredNote = try #require(
            try BackupTestUtil.fetchByID(CDNote.self, noteID, entityName: "Note", in: restored)
        )
        #expect(Self.links(of: restoredNote) == expected)
    }

    @Test("A Merge sets a link to what the row names, or to nothing, and leaves one it doesn't name")
    func mergeRelinksWhatTheRowNames() async throws {
        let (stack, note) = try Self.linkedFixture()
        let context = stack.viewContext
        let noteID = try #require(note.id)
        let issueID = try #require(note.issue?.id)
        let otherWork = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Other work", studentID: UUID(), lessonID: UUID()
        )
        let otherWorkID = try #require(otherWork.id)
        #expect(CoreDataTestHelpers.save(context))

        var backup = Fix1102.payload(of: context)
        let row = try #require(backup.notes.firstIndex { $0.id == noteID })
        // The backup's note is newer than this device's, so a Merge takes it.
        backup.notes[row].values["updatedAt"] = .date(Fix1102.at(50))
        backup.notes[row].values["workID"] = .uuid(otherWorkID)
        // An assignment this notebook doesn't have.
        backup.notes[row].values["lessonAssignmentID"] = .uuid(UUID())
        // A row from before the note pointed at the issue.
        backup.notes[row].values["issueID"] = nil

        try await Fix1102.restore(backup, into: context, mode: .merge)

        let restored = try #require(
            try BackupTestUtil.fetchByID(CDNote.self, noteID, entityName: "Note", in: context)
        )
        #expect(restored.updatedAt == Fix1102.at(50), "the Merge took the backup's note")
        #expect(restored.work?.id == otherWorkID, "set to the work the row names")
        #expect(restored.lessonAssignment == nil, "set to nothing: the row's assignment isn't here")
        #expect(restored.issue?.id == issueID, "left as it is: the row names no issue")
        #expect(restored.workCheckIn != nil && restored.studentMeeting != nil, "the row's other links stay")
    }
}
