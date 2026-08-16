import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Presentation Outcome Persistence")
@MainActor
final class PresentationOutcomePersistenceTests {
    private func makeFixture() throws -> (
        context: NSManagedObjectContext,
        lesson: CDLesson,
        students: [CDStudent],
        assignment: CDLessonAssignment
    ) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let students = [
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada"),
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        ]
        let studentIDs = students.compactMap(\.id)
        let assignment = PresentationFactory.makeDraft(
            lessonID: try #require(lesson.id),
            studentIDs: studentIDs,
            context: context
        )
        assignment.lesson = lesson
        return (context, lesson, students, assignment)
    }

    @Test("Group and individual observations attach to the exact presentation")
    func persistsScopedObservations() throws {
        let fixture = try makeFixture()
        let studentIDs = fixture.students.compactMap(\.id)
        let firstID = try #require(studentIDs.first)

        let created = try PresentationOutcomePersistenceService.persistObservations(
            groupObservation: "The group worked quietly through the exchange.",
            studentObservations: [firstID: "Counted each category independently."],
            studentIDs: studentIDs,
            presentationID: fixture.assignment.id,
            context: fixture.context
        )

        #expect(created.count == 2)
        #expect(created.allSatisfy { $0.lessonAssignment === fixture.assignment })
        #expect(created.allSatisfy { $0.lessonID == fixture.lesson.id?.uuidString })

        let groupNote = try #require(created.first { $0.body.hasPrefix("The group") })
        if case .students(let linkedIDs) = groupNote.scope {
            #expect(Set(linkedIDs) == Set(studentIDs))
        } else {
            Issue.record("The shared observation should retain the group student scope")
        }

        let links = (groupNote.studentLinks?.allObjects as? [CDNoteStudentLink]) ?? []
        #expect(Set(links.map(\.studentID)) == Set(studentIDs.map(\.uuidString)))
        #expect(links.allSatisfy { $0.noteID == groupNote.id?.uuidString })
    }

    @Test("Blank observations are ignored and retrying does not duplicate notes")
    func ignoresBlanksAndIsIdempotent() throws {
        let fixture = try makeFixture()
        let studentIDs = fixture.students.compactMap(\.id)
        let firstID = try #require(studentIDs.first)
        let payload = [firstID: "  Chose the material again.  "]

        let firstSave = try PresentationOutcomePersistenceService.persistObservations(
            groupObservation: "   ",
            studentObservations: payload,
            studentIDs: studentIDs,
            presentationID: fixture.assignment.id,
            context: fixture.context
        )
        let retry = try PresentationOutcomePersistenceService.persistObservations(
            groupObservation: "",
            studentObservations: payload,
            studentIDs: studentIDs,
            presentationID: fixture.assignment.id,
            context: fixture.context
        )

        #expect(firstSave.count == 1)
        #expect(firstSave.first?.body == "Chose the material again.")
        #expect(retry.isEmpty)
        #expect(fixture.assignment.unifiedNotes?.count == 1)
    }

    @Test("A missing presentation identity fails instead of guessing")
    func missingPresentationIDFails() throws {
        let fixture = try makeFixture()

        #expect(throws: PresentationOutcomePersistenceService.PersistenceError.self) {
            try PresentationOutcomePersistenceService.persistObservations(
                groupObservation: "Observed something important.",
                studentObservations: [:],
                studentIDs: fixture.students.compactMap(\.id),
                presentationID: nil,
                context: fixture.context
            )
        }
        #expect(fixture.assignment.unifiedNotes?.count == 0)
    }

    @Test("Observations never acquire a student outside the presentation")
    func ignoresStudentsOutsideAssignment() throws {
        let fixture = try makeFixture()
        let validID = try #require(fixture.students.first?.id)
        let foreignID = UUID()

        let notes = try PresentationOutcomePersistenceService.persistObservations(
            groupObservation: "Shared factual observation.",
            studentObservations: [
                validID: "Valid child observation.",
                foreignID: "This child was not in the presentation."
            ],
            studentIDs: [validID, foreignID],
            presentationID: fixture.assignment.id,
            context: fixture.context
        )

        #expect(notes.count == 2)
        #expect(notes.allSatisfy { !$0.scope.applies(to: foreignID) })
        #expect(notes.contains { $0.body == "Valid child observation." })
        #expect(!notes.contains { $0.body.contains("not in the presentation") })
    }

    @Test("Follow-up work stays linked to the supplied repeat presentation")
    func followUpWorkUsesExactPresentation() throws {
        let fixture = try makeFixture()
        let studentID = try #require(fixture.students.first?.id)
        let lessonID = try #require(fixture.lesson.id)

        let earlier = PresentationFactory.makePresented(
            lessonID: lessonID,
            studentIDs: [studentID],
            presentedAt: Date().addingTimeInterval(-86_400),
            context: fixture.context
        )
        fixture.assignment.markPresented()

        let work = try WorkRepository(context: fixture.context).createWork(
            studentID: studentID,
            lessonID: lessonID,
            title: "Repeat the exchange game",
            kind: .practiceLesson,
            presentationID: fixture.assignment.id
        )

        #expect(work.presentationID == fixture.assignment.id?.uuidString)
        #expect(work.presentationID != earlier.id?.uuidString)
    }
}
