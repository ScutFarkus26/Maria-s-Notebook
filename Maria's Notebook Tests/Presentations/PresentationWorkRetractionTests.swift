import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

// The mismatch this guards against runs backwards in time: the follow-up
// service generates work from a presentation's participant list, and the
// guide later edits that list by hand. Removing a child from the presentation
// must name the work she is still on and, on request, take her off it.

@Suite("Presentation Work Retraction")
@MainActor
struct PresentationWorkRetractionTests {

    private struct Fixture {
        let context: NSManagedObjectContext
        let assignment: CDLessonAssignment
        let lessonID: UUID
        let students: [CDStudent]
    }

    private func makeFixture(childCount: Int = 3) throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Commutative Law")
        let students = (0..<childCount).map {
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Child \($0 + 1)", lastName: "Test")
        }
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: students, context: context)
        assignment.markPresented(at: Date())
        CoreDataTestHelpers.save(context)
        return Fixture(context: context, assignment: assignment, lessonID: try #require(lesson.id), students: students)
    }

    /// Work the way the follow-up service leaves it: one row per child,
    /// linked to the presentation, owner as participant.
    private func seedGeneratedWork(for fixture: Fixture) throws -> [CDWorkModel] {
        let repository = WorkRepository(context: fixture.context)
        let presentationID = try #require(fixture.assignment.id)
        let works = try fixture.students.map { student in
            let work = try repository.createWork(
                studentID: try #require(student.id), lessonID: fixture.lessonID,
                title: "Define commutative property", kind: .followUpAssignment,
                presentationID: presentationID, saveImmediately: false
            )
            work.sourceContextType = .presentation
            work.sourceContextID = presentationID.uuidString
            return work
        }
        CoreDataTestHelpers.save(fixture.context)
        return works
    }

    @Test("generated work is found by presentation id or by source context")
    func generatedWorkIsFoundEitherWay() throws {
        let fixture = try makeFixture(childCount: 2)
        let works = try seedGeneratedWork(for: fixture)
        // Strip the presentation link from one row; the source context still points home.
        works[1].presentationID = nil
        let stranger = CoreDataTestHelpers.seedWorkModel(in: fixture.context, lessonID: fixture.lessonID)
        CoreDataTestHelpers.save(fixture.context)

        let found = PresentationWorkRetraction.generatedWork(for: fixture.assignment, in: fixture.context)
        #expect(Set(found.map(\.objectID)) == Set(works.map(\.objectID)))
        #expect(!found.contains { $0 === stranger })
    }

    @Test("removing a child from the presentation names her own generated row")
    func removalNamesHerRow() throws {
        let fixture = try makeFixture()
        let works = try seedGeneratedWork(for: fixture)
        let naomi = try #require(fixture.students[0].id)

        let plans = PresentationWorkRetraction.plans(
            forRemoving: [naomi], from: fixture.assignment, in: fixture.context
        )
        // Her row is single-child: taking her off would empty it, so it is
        // reported as untouched rather than deleted behind the guide's back.
        #expect(plans.isEmpty)
        #expect(works.allSatisfy { !$0.isDeleted })
    }

    @Test("a passenger on another child's generated row comes off it on apply")
    func passengerComesOffOnApply() throws {
        let fixture = try makeFixture()
        let works = try seedGeneratedWork(for: fixture)
        let naomi = try #require(fixture.students[0].id)
        let ora = try #require(fixture.students[1].id)
        let orasRow = try #require(works.first { $0.studentID == ora.uuidString })
        let passenger = CDWorkParticipantEntity(context: fixture.context)
        passenger.studentID = naomi.uuidString
        passenger.work = orasRow
        CoreDataTestHelpers.save(fixture.context)

        let plans = PresentationWorkRetraction.plans(
            forRemoving: [naomi], from: fixture.assignment, in: fixture.context
        )
        #expect(plans.count == 1)
        #expect(plans[0].steps.map(\.action) == [.dropParticipant])
        let lines = PresentationWorkRetraction.describe(plans, in: fixture.context)
        #expect(lines == ["Child 1 T comes off “Define commutative property”"])

        try PresentationWorkRetraction.apply(plans, in: fixture.context)
        CoreDataTestHelpers.save(fixture.context)

        #expect(WorkGrouping.studentIDs(of: orasRow) == [ora])
        #expect(!orasRow.isDeleted)
    }

    @Test("children who stay on the presentation are not planned for")
    func stayingChildrenAreUntouched() throws {
        let fixture = try makeFixture()
        _ = try seedGeneratedWork(for: fixture)

        let plans = PresentationWorkRetraction.plans(
            forRemoving: [], from: fixture.assignment, in: fixture.context
        )
        #expect(plans.isEmpty)
    }
}
