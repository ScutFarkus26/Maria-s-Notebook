import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Model helper fixes from the 2026-10-05 data-model hunt: setters and
// initializers that wrote something other than what they were given.

@Suite("Model helper fixes")
@MainActor
struct ModelHelperFixesTests {

    // MARK: - #43 A lesson lookup that finds nothing keeps the lesson id

    @Test("Setting a presentation's lesson to nil leaves its lesson id alone")
    func lessonSetterIgnoresNil() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lessonID = UUID()
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = lessonID.uuidString

        assignment.lesson = nil
        #expect(assignment.lessonID == lessonID.uuidString)

        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        assignment.lesson = lesson
        #expect(assignment.lessonID == lesson.id?.uuidString)
    }

    @Test("Editing a presentation whose lesson isn't in the list keeps the chosen lesson id")
    func detailEditKeepsLessonIDWhenLessonNotLoaded() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context)
        let studentID = try #require(student.id)
        let assignment = CDLessonAssignment(context: context)
        assignment.studentIDs = [studentID.uuidString]
        let chosen = UUID()

        PresentationDetailActions().applyEditsToModel(
            lessonAssignment: assignment,
            editingLessonID: chosen,
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false,
            notes: "",
            needsAnotherPresentation: false,
            selectedStudentIDs: [studentID],
            studentsAll: [student],
            lessons: [],
            calendar: AppCalendar.shared
        )
        #expect(assignment.lessonID == chosen.uuidString)
    }

    // MARK: - #44 A new note's scope index agrees with its scope

    @Test("A new note is whole-class in its scope and in its search index")
    func newNoteIsIndexedAsAll() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let note = CDNote(context: context)
        #expect(note.scopeBlob != nil)
        #expect(note.scopeIsAll)
        #expect(note.searchIndexStudentID == nil)
        if case .all = note.scope {} else { Issue.record("expected .all, got \(note.scope)") }
    }

    @Test("The repair marks only blob-less notes with an unset index, and a second run finds nothing")
    func repairMissingNoteScopeIndex() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        func legacy(_ body: String) -> CDNote {
            let note = CoreDataTestHelpers.seedNote(in: context, body: body)
            note.scopeBlob = nil
            note.scopeIsAll = false
            note.searchIndexStudentID = nil
            return note
        }
        let unscoped = legacy("Whole class went outside")
        let named = legacy("Read with Maya")
        named.searchIndexStudentID = child
        let linked = legacy("Worked with two friends")
        let link = CDNoteStudentLink(context: context)
        link.noteID = linked.id?.uuidString ?? ""
        link.studentID = child.uuidString
        link.note = linked
        let scoped = CoreDataTestHelpers.seedNote(in: context, body: "Counted to 100")
        scoped.scope = .students([child, UUID()])
        CoreDataTestHelpers.save(context)

        #expect(DataCleanupService.repairMissingNoteScopeIndex(using: context) == 1)
        #expect(unscoped.scopeIsAll)
        #expect(unscoped.scopeBlob == nil)
        #expect(!named.scopeIsAll)
        #expect(!linked.scopeIsAll)
        #expect(!scoped.scopeIsAll)
        #expect(context.updatedObjects == [unscoped])
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.repairMissingNoteScopeIndex(using: context) == 0)
        #expect(!context.hasChanges)

        let wholeClass = CDFetchRequest(CDNote.self)
        wholeClass.predicate = NSPredicate(format: "scopeIsAll == YES")
        #expect(context.safeFetch(wholeClass).map(\.body) == ["Whole class went outside"])
    }

    // MARK: - #46 A reminder's completion keeps its moment

    @Test("Marking a reminder done stores the moment, not the start of the day")
    func markCompletedStoresMoment() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let reminder = CDReminder(context: context)
        let before = Date()
        reminder.markCompleted()
        let after = Date()
        let completedAt = try #require(reminder.completedAt)
        #expect(completedAt >= before && completedAt <= after)
        #expect(reminder.isCompleted)
    }

    // MARK: - #47 No birthday means no birthday

    @Test("A new student has no birthday until one is given")
    func newStudentHasNoBirthday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        #expect(CDStudent(context: context).birthday == nil)
    }

    @Test("A spreadsheet row with no birthday imports a student with no birthday")
    func csvImportLeavesMissingBirthdayNil() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let born = try CoreDataTestHelpers.day("2017-03-02")
        let parsed = StudentCSVImporter.Parsed(
            rows: [
                StudentCSVImporter.Row(firstName: "Ada", lastName: "Lovelace", birthday: nil),
                StudentCSVImporter.Row(firstName: "Ora", lastName: "Katz", birthday: born)
            ],
            totalRows: 2, potentialDuplicates: [], warnings: []
        )
        let summary = try StudentCSVImporter.commit(parsed: parsed, into: context, existingStudents: [])
        #expect(summary.insertedCount == 2)
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        let ada = try #require(students.first { $0.firstName == "Ada" })
        let ora = try #require(students.first { $0.firstName == "Ora" })
        #expect(ada.birthday == nil)
        #expect(ora.birthday == born)
    }

    // MARK: - #58 Evidence this build doesn't know survives an edit

    @Test("Editing follow-up evidence keeps tokens a newer version wrote")
    func unknownEvidenceTokensKept() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let presentation = CDLessonPresentation(context: context)
        presentation.followUpEvidenceRaw = "concentrated,taughtAnother"

        var evidence = presentation.followUpEvidence
        #expect(evidence == [.concentrated])
        evidence.insert(.choseIndependently)
        presentation.followUpEvidence = evidence
        #expect(presentation.followUpEvidenceRaw == "choseIndependently,concentrated,taughtAnother")

        presentation.followUpEvidence = []
        #expect(presentation.followUpEvidenceRaw == "taughtAnother")
    }

    @Test("Clearing every known and unknown token leaves no evidence")
    func emptyEvidenceIsNil() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let presentation = CDLessonPresentation(context: context)
        presentation.followUpEvidence = [.concentrated]
        #expect(presentation.followUpEvidenceRaw == "concentrated")
        presentation.followUpEvidence = []
        #expect(presentation.followUpEvidenceRaw == nil)
    }

    // MARK: - #60 Clearing a meeting's work writes nil

    @Test("Setting a scheduled meeting's work to nil clears workID to nil, not an empty string")
    func meetingWorkIDClearsToNil() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let meeting = CDScheduledMeeting(context: context)
        let workID = UUID()
        meeting.workIDUUID = workID
        #expect(meeting.workID == workID.uuidString)
        meeting.workIDUUID = nil
        #expect(meeting.workID == nil)
    }
}
