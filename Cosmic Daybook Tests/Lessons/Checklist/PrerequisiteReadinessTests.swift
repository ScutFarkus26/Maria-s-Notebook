import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Domain-logic review A6: a lesson's prerequisites from other sequences were
/// stored, shown and backed up but read by nothing. A prerequisite she hasn't
/// been given now holds her at "Ready, check first" with its reason, on the
/// Checklist and in the ready queue alike (the screens prefix "Check first: ").
@Suite("Prerequisite readiness (domain logic A6)")
@MainActor
struct PrerequisiteReadinessTests {

    /// Math › Fractions: F0, then F1, whose prerequisite is Geometry's
    /// "Equivalent Figures".
    private struct Fixture {
        let context: NSManagedObjectContext
        let maya: CDStudent
        let prerequisite: CDLesson
        let f0: CDLesson
        let f1: CDLesson

        var lessons: [CDLesson] { [f0, f1] }

        func give(_ lesson: CDLesson, confirming: Bool) throws {
            let given = CDLessonAssignment(context: context)
            given.lessonID = try #require(lesson.id).uuidString
            given.studentIDs = [maya.cloudKitKey]
            given.markPresented(at: try CoreDataTestHelpers.day("2026-09-08"), snapshotLesson: false)
            if confirming { given.confirmStudent(try #require(maya.id)) }
            try context.save()
        }

        func cell(_ lesson: CDLesson) throws -> StudentChecklistRowState {
            let matrix = ClassGridEngine.buildMatrix(students: [maya], lessons: lessons, context: context)
            let studentID = try #require(maya.id)
            let lessonID = try #require(lesson.id)
            return try #require(matrix[studentID]?[lessonID])
        }

        func queueItem(for lesson: CDLesson) throws -> ReadyForNextItem? {
            let studentID = try #require(maya.id).uuidString
            let index = PresentationRecordIndex(students: [studentID], in: context)
            let library = context.safeFetch(CDFetchRequest(CDLesson.self))
            let lessonID = try #require(lesson.id).uuidString
            return ReadyForNextEngine.items(studentIDs: [studentID], lessons: library, index: index, in: context)
                .first { $0.nextLessonID == lessonID }
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let prerequisite = CoreDataTestHelpers.seedLesson(
            in: context, name: "Equivalent Figures", area: "Geometry", sequence: "Equivalence"
        )
        let f0 = CoreDataTestHelpers.seedLesson(in: context, name: "Fractions 0", area: "Math", sequence: "Fractions")
        f0.orderInSequence = 0
        let f1 = CoreDataTestHelpers.seedLesson(in: context, name: "Fractions 1", area: "Math", sequence: "Fractions")
        f1.orderInSequence = 1
        f1.prerequisiteLessonUUIDs = [try #require(prerequisite.id)]
        try context.save()
        return Fixture(context: context, maya: maya, prerequisite: prerequisite, f0: f0, f1: f1)
    }

    @Test("a prerequisite not yet presented holds her at check first, with its reason, on the Checklist")
    func checklistNamesThePrerequisite() throws {
        let fixture = try makeFixture()
        try fixture.give(fixture.f0, confirming: true)

        let cell = try fixture.cell(fixture.f1)
        #expect(cell.blockingReason == .none)
        #expect(cell.checkFirstReasons == ["Equivalent Figures not yet presented"])
        #expect(ChecklistCellDescription.checkFirstText(cell) == "Equivalent Figures not yet presented")
    }

    @Test("the first lesson of a sequence is held too when its prerequisite is missing")
    func firstLessonOfASequence() throws {
        let fixture = try makeFixture()
        fixture.f0.prerequisiteLessonUUIDs = [try #require(fixture.prerequisite.id)]
        try fixture.context.save()

        let cell = try fixture.cell(fixture.f0)
        #expect(cell.checkFirstReasons == ["Equivalent Figures not yet presented"])
    }

    @Test("the ready queue holds her at check first with the same reason")
    func readyQueueNamesThePrerequisite() throws {
        let fixture = try makeFixture()
        try fixture.give(fixture.f0, confirming: true)

        let item = try #require(try fixture.queueItem(for: fixture.f1))
        #expect(item.tier == .almostReady)
        #expect(item.reasons == ["Equivalent Figures not yet presented"])
    }

    @Test("once the prerequisite is given she is plainly ready, on both")
    func givenPrerequisiteClears() throws {
        let fixture = try makeFixture()
        try fixture.give(fixture.f0, confirming: true)
        try fixture.give(fixture.prerequisite, confirming: false)

        #expect(try fixture.cell(fixture.f1).checkFirstReasons.isEmpty)
        #expect(try fixture.queueItem(for: fixture.f1)?.tier == .ready)
    }
}
