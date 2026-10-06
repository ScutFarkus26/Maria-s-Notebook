import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #23. Recording a presentation took every child
// it couldn't find off the lesson, and that synced: a student still on her
// way from iCloud, or named by an id written in lower case, lost the lesson
// on every device. The launch cleanups likewise read a lower-cased real id
// as a missing student. Unknown ids now stay on the lesson (they just get no
// history row), and ids are compared trimmed and upper-cased everywhere.

@Suite("Unknown and lower-cased student ids are kept")
@MainActor
struct UnknownStudentIDTests {
    private typealias Fixture = LaunchRepairFixture

    private func historyStudentIDs(
        for assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) -> Set<String> {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "presentationID == %@", assignment.id?.uuidString ?? "")
        return Set(context.safeFetch(request).map(\.studentID))
    }

    @Test("Recording keeps a child who isn't here yet on the lesson, with no history row for her")
    func unknownChildStaysOnTheLesson() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "", sequence: "")
        let ada = try #require(CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada").id).uuidString
        let notHereYet = UUID().uuidString
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = try #require(lesson.id).uuidString
        assignment.studentIDs = [ada, notHereYet]

        _ = try LifecycleService.recordPresentation(from: assignment, presentedAt: Date(), modelContext: context)

        #expect(assignment.studentIDs == [ada, notHereYet])
        #expect(historyStudentIDs(for: assignment, in: context) == [ada])
    }

    @Test("A child named by a lower-cased or padded id is recorded under her own id")
    func lowerCasedChildIsRecorded() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame", area: "", sequence: "")
        let ben = try #require(CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben").id).uuidString
        let cy = try #require(CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy").id).uuidString
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = try #require(lesson.id).uuidString
        assignment.studentIDs = [ben.lowercased(), " \(cy) "]

        _ = try LifecycleService.recordPresentation(from: assignment, presentedAt: Date(), modelContext: context)

        #expect(assignment.studentIDs == [ben.lowercased(), " \(cy) "])
        #expect(historyStudentIDs(for: assignment, in: context) == [ben, cy])
    }

    @Test("The launch cleanups keep a real student named in lower case")
    func launchCleanupsKeepLowerCasedIDs() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try Fixture.seed(stack.viewContext)

        let outcome = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false
        ) { _ in [:] }

        let result = Fixture.snapshot(of: stack.viewContext)
        let cy = Fixture.cy.uuidString
        // Work 5 and assignment 3 name Cy in lower case; the ids of students
        // no longer on file still go.
        #expect(result.workStudents[Fixture.workID(5)] == cy.lowercased())
        #expect(result.assignmentStudents[Fixture.assignmentID(3)] == [cy.lowercased()])
        #expect(result.workStudents[Fixture.workID(2)] == "")
        #expect(outcome.workRowsCleaned == 4)
    }
}
