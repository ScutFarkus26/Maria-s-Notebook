import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Sequence Recap note visibility")
@MainActor
final class SequenceRecapVisibilityTests {

    private struct Fixture {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let firstStudent: CDStudent
        let secondStudent: CDStudent
        let assignment: CDLessonAssignment
    }

    private func makeFixture() throws -> Fixture {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let lesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "Decimal System",
            area: "Math",
            sequence: "Number Work"
        )
        lesson.id = UUID()
        lesson.orderInSequence = 1

        let firstStudent = CoreDataTestHelpers.seedStudent(
            in: context,
            firstName: "Ari",
            lastName: "Aleph"
        )
        firstStudent.id = UUID()

        let secondStudent = CoreDataTestHelpers.seedStudent(
            in: context,
            firstName: "Bina",
            lastName: "Bet"
        )
        secondStudent.id = UUID()

        let assignment = PresentationFactory.makePresented(
            lessonID: try #require(lesson.id),
            studentIDs: [
                try #require(firstStudent.id),
                try #require(secondStudent.id)
            ],
            context: context
        )

        return Fixture(
            context: context,
            lesson: lesson,
            firstStudent: firstStudent,
            secondStudent: secondStudent,
            assignment: assignment
        )
    }

    @discardableResult
    private func makeNote(
        _ body: String,
        scope: NoteScope,
        in context: NSManagedObjectContext
    ) -> CDNote {
        let note = CDNote(context: context)
        note.body = body
        note.scope = scope
        return note
    }

    @Test("Loader follows presentation, work, and check-in relationships back to the lesson")
    func loaderIncludesRelationshipScopedNotes() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let studentID = try #require(fixture.firstStudent.id)
        let lessonID = try #require(fixture.lesson.id)
        let assignmentID = try #require(fixture.assignment.id)

        let presentationNote = makeNote("Presentation observation", scope: .student(studentID), in: context)
        presentationNote.lessonAssignment = fixture.assignment

        let work = CDWorkModel(context: context)
        work.title = "Stamp Game practice"
        work.studentID = studentID.uuidString
        work.lessonID = lessonID.uuidString
        work.presentationID = assignmentID.uuidString

        let workNote = makeNote("Work observation", scope: .student(studentID), in: context)
        workNote.work = work

        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = try #require(work.id).uuidString
        checkIn.work = work

        let checkInNote = makeNote("Check-in observation", scope: .student(studentID), in: context)
        checkInNote.workCheckIn = checkIn

        let directLessonNote = makeNote("Direct lesson note", scope: .student(studentID), in: context)
        directLessonNote.lessonID = lessonID.uuidString

        #expect(presentationNote.lessonID == nil)
        #expect(workNote.lessonID == nil)
        #expect(checkInNote.lessonID == nil)
        #expect(context.safeSave())

        let collected = SequenceRecapDataLoader.collect(
            lessonIDs: [lessonID.uuidString],
            studentIDs: [studentID.uuidString],
            context: context
        )

        #expect(Set(collected.notes.map(\.body)) == Set([
            "Presentation observation",
            "Work observation",
            "Check-in observation",
            "Direct lesson note"
        ]))
    }

    @Test("A child-specific presentation note is not shown under a peer")
    func resolverHonorsPresentationNoteScope() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let firstID = try #require(fixture.firstStudent.id)
        let secondID = try #require(fixture.secondStudent.id)

        let groupNote = makeNote(
            "The group repeated the exchange together.",
            scope: .students([firstID, secondID]),
            in: context
        )
        groupNote.lessonAssignment = fixture.assignment

        let firstOnlyNote = makeNote(
            "Ari independently reconstructed the layout.",
            scope: .student(firstID),
            in: context
        )
        firstOnlyNote.lessonAssignment = fixture.assignment

        // Deliberately do not create NoteStudentLink rows here. The encoded NoteScope
        // remains the source of truth and must be sufficient for recap visibility.
        #expect(context.safeSave())

        let recap = try #require(SequenceRecapResolver.resolve(
            currentLesson: fixture.lesson,
            students: [fixture.firstStudent, fixture.secondStudent],
            context: context
        ))

        let firstBodies = try attachedNoteBodies(
            in: recap,
            studentID: firstID,
            lessonID: try #require(fixture.lesson.id),
            assignmentID: try #require(fixture.assignment.id)
        )
        let secondBodies = try attachedNoteBodies(
            in: recap,
            studentID: secondID,
            lessonID: try #require(fixture.lesson.id),
            assignmentID: try #require(fixture.assignment.id)
        )

        #expect(firstBodies == Set([
            "The group repeated the exchange together.",
            "Ari independently reconstructed the layout."
        ]))
        #expect(secondBodies == Set([
            "The group repeated the exchange together."
        ]))
    }

    @Test("Relationship-only work and check-in notes appear in the work timeline")
    func resolverShowsWorkAndCheckInNotes() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let studentID = try #require(fixture.firstStudent.id)
        let lessonID = try #require(fixture.lesson.id)
        let assignmentID = try #require(fixture.assignment.id)

        let work = CDWorkModel(context: context)
        work.title = "Golden Bead exchange"
        work.studentID = studentID.uuidString
        work.lessonID = lessonID.uuidString
        work.presentationID = assignmentID.uuidString

        let workNote = makeNote("Selected the material again after lunch.", scope: .student(studentID), in: context)
        workNote.work = work

        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = try #require(work.id).uuidString
        checkIn.work = work

        let checkInNote = makeNote("Completed two exchanges without prompting.", scope: .student(studentID), in: context)
        checkInNote.workCheckIn = checkIn

        #expect(context.safeSave())

        let recap = try #require(SequenceRecapResolver.resolve(
            currentLesson: fixture.lesson,
            students: [fixture.firstStudent],
            context: context
        ))
        let studentEntry = try #require(recap.studentEntries.first { $0.id == studentID })
        let lessonEntry = try #require(studentEntry.lessonEntries.first { $0.id == lessonID })
        let presentation = try #require(lessonEntry.presentations.first { $0.id == assignmentID })
        let workSnapshot = try #require(presentation.workItems.first { $0.id == work.id })
        let checkInSnapshot = try #require(workSnapshot.checkIns.first { $0.id == checkIn.id })

        #expect(workSnapshot.attachedNotes.map(\.body) == ["Selected the material again after lunch."])
        #expect(checkInSnapshot.notes.map(\.body) == ["Completed two exchanges without prompting."])
    }

    private func attachedNoteBodies(
        in recap: SequenceRecap,
        studentID: UUID,
        lessonID: UUID,
        assignmentID: UUID
    ) throws -> Set<String> {
        let studentEntry = try #require(recap.studentEntries.first { $0.id == studentID })
        let lessonEntry = try #require(studentEntry.lessonEntries.first { $0.id == lessonID })
        let presentation = try #require(lessonEntry.presentations.first { $0.id == assignmentID })
        return Set(presentation.attachedNotes.map(\.body))
    }
}
