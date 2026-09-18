import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Capture Follow-Up Persistence")
@MainActor
struct CaptureFollowUpPersistenceTests {

    private struct Fixture {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let student: CDStudent
        let assignment: CDLessonAssignment
    }

    private func makeFixture() throws -> Fixture {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let assignment = PresentationFactory.makePresented(
            lesson: lesson, students: [student], context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        return Fixture(context: context, lesson: lesson, student: student, assignment: assignment)
    }

    private func assignments(in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
    }

    /// The "re-present" decision for this child, as the capture review makes it.
    private func represent(
        _ fixture: Fixture, studentID: UUID
    ) -> (entry: CaptureFollowUpPersistence.Entry, persistence: CapturePersistenceContext)? {
        guard let lessonID = fixture.lesson.id, let presentationID = fixture.assignment.id else {
            return nil
        }
        let entry = CaptureFollowUpPersistence.Entry(
            studentID: studentID,
            observation: "Lost the place borrowing; wants it again.",
            followUp: .represent,
            followUpDetail: ""
        )
        let persistence = CapturePersistenceContext(
            lessonID: lessonID,
            lessonName: fixture.lesson.name,
            presentationID: presentationID,
            context: fixture.context
        )
        return (entry, persistence)
    }

    /// Runs the re-present decision `times` over, the way a second review of
    /// the same presentation would, and hands back the drafts it left.
    private func persistRepresent(_ fixture: Fixture, times: Int) throws -> [CDLessonAssignment] {
        let studentID: UUID = try #require(fixture.student.id)
        let decision = try #require(represent(fixture, studentID: studentID))
        for _ in 0..<times {
            try CaptureFollowUpPersistence.persist(
                [decision.entry], assignment: fixture.assignment,
                lesson: fixture.lesson, persistence: decision.persistence
            )
        }
        #expect(CoreDataTestHelpers.save(fixture.context))
        return assignments(in: fixture.context).filter { !$0.isPresented }
    }

    @Test("re-present flags the record that did not take and says so on the draft")
    func representFlagsThePriorRecord() throws {
        let fixture: Fixture = try makeFixture()
        let drafts: [CDLessonAssignment] = try persistRepresent(fixture, times: 1)
        let flagged: Bool = fixture.assignment.needsAnotherPresentation
        let madeFor: UUID? = drafts.first?.studentUUIDs.first
        let notes: String? = drafts.first?.notes
        #expect(drafts.count == 1)
        #expect(flagged)
        #expect(madeFor == fixture.student.id && notes == Self.expectedSecondPassNote)
    }

    /// The line `createRepresentationIfNeeded` writes on the draft it makes.
    private static var expectedSecondPassNote: String {
        MCPNotebookTools.RepeatPurpose.secondPass.noteLine(plannedOn: Date())
    }

    @Test("a second review of the same presentation does not stack a second draft")
    func representDraftsOnlyOnce() throws {
        let fixture: Fixture = try makeFixture()
        let drafts: [CDLessonAssignment] = try persistRepresent(fixture, times: 2)
        #expect(drafts.count == 1)
    }
}
