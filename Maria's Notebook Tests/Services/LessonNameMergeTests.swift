import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

// Geometry › Area held Rectangle, Parallelogram and the three triangles twice
// each (2026-09-09), and every child's year plan doubled with them. The merge
// keeps the older record and moves everything onto it; the repository refuses
// the same name in the same sub-area so it cannot happen again.

@Suite("Lesson Name Merge")
@MainActor
struct LessonNameMergeTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func lessons(in context: NSManagedObjectContext) -> [CDLesson] {
        context.safeFetch(CDFetchRequest(CDLesson.self))
    }

    @discardableResult
    private func seedAreaLesson(
        _ name: String, order: Int64, in context: NSManagedObjectContext, sequence: String = "Area"
    ) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: "Geometry", sequence: sequence)
        lesson.orderInSequence = order
        return lesson
    }

    // MARK: - Detection

    @Test("Same name in the same sub-area is a duplicate; other sub-areas and parsha lessons are not")
    func detectsOnlySameSubAreaDuplicates() throws {
        let context = try makeContext()
        seedAreaLesson("Rectangle", order: 0, in: context)
        seedAreaLesson("rectangle ", order: 5, in: context)
        seedAreaLesson("Triangle and Rectangle", order: 10, in: context)
        seedAreaLesson("Triangle and Rectangle", order: 5, in: context, sequence: "Further Exploration of Equivalence")
        let weekOne = CoreDataTestHelpers.seedLesson(in: context, name: "Middle Girls", area: "Parsha", sequence: "")
        weekOne.parshaKey = "bereishit"
        let weekTwo = CoreDataTestHelpers.seedLesson(in: context, name: "Middle Girls", area: "Parsha", sequence: "")
        weekTwo.parshaKey = "noach"
        CoreDataTestHelpers.save(context)

        let groups = DataCleanupService.sameNameLessonGroups(using: context)
        #expect(groups.count == 1)
        #expect(Set(groups.first?.map(\.name) ?? []) == ["Rectangle", "rectangle "])
    }

    // MARK: - Merge

    @Test("Merge keeps the older record and repoints presentations, marks, plans and work at it")
    func mergeRepointsEverything() throws {
        let context = try makeContext()
        let older = seedAreaLesson("Parallelogram", order: 1, in: context)
        let newer = seedAreaLesson("Parallelogram", order: 6, in: context)
        newer.writeUp = "Cut and rearrange the parallelogram into a rectangle."
        newer.isKeyLesson = true
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.save(context)
        let olderID = try #require(older.id)
        let newerID = try #require(newer.id)
        let studentID = try #require(student.id)

        let presentation = CDLessonAssignment(context: context)
        presentation.lessonID = newerID.uuidString
        presentation.studentIDs = [studentID.uuidString]
        presentation.stateRaw = LessonAssignmentState.presented.rawValue
        presentation.presentedAt = Date()

        let mark = CDLessonPresentation(context: context)
        mark.lessonID = newerID.uuidString
        mark.studentID = studentID.uuidString
        mark.masteredAt = Date()

        let plannedOnOlder = CDYearPlanEntry(context: context)
        plannedOnOlder.lessonID = olderID.uuidString
        plannedOnOlder.studentID = studentID.uuidString
        plannedOnOlder.status = .planned
        let promotedOnNewer = CDYearPlanEntry(context: context)
        promotedOnNewer.lessonID = newerID.uuidString
        promotedOnNewer.studentID = studentID.uuidString
        promotedOnNewer.status = .promoted

        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Parallelogram follow-up", studentID: studentID, lessonID: newerID
        )
        let follower = seedAreaLesson("Acute Angled Triangle", order: 2, in: context)
        follower.prerequisiteLessonIDs = "\(newerID.uuidString),\(olderID.uuidString)"
        CoreDataTestHelpers.save(context)

        let removed = DataCleanupService.mergeSameNameLessons(using: context)
        #expect(removed == 1)
        CoreDataTestHelpers.save(context)

        let survivors = lessons(in: context).filter { $0.name == "Parallelogram" }
        #expect(survivors.count == 1)
        let survivor = try #require(survivors.first)
        #expect(survivor.id == olderID)
        #expect(survivor.writeUp == "Cut and rearrange the parallelogram into a rectangle.")
        #expect(survivor.isKeyLesson)

        #expect(presentation.lessonID == olderID.uuidString)
        #expect(mark.lessonID == olderID.uuidString)
        #expect(work.lessonID == olderID.uuidString)
        #expect(follower.prerequisiteLessonIDs == olderID.uuidString)

        let plan = context.safeFetch(CDFetchRequest(CDYearPlanEntry.self))
        #expect(plan.count == 1)
        #expect(plan.first?.lessonID == olderID.uuidString)
        #expect(plan.first?.status == .promoted)
    }

    @Test("A child left with two marks for one lesson keeps the earlier one with the later mastery date")
    func mergeFoldsDuplicateMarks() throws {
        let context = try makeContext()
        let older = seedAreaLesson("Rectangle", order: 0, in: context)
        let newer = seedAreaLesson("Rectangle", order: 5, in: context)
        CoreDataTestHelpers.save(context)
        let studentID = UUID()
        let mastered = Date()

        let onOlder = CDLessonPresentation(context: context)
        onOlder.lessonID = try #require(older.id).uuidString
        onOlder.studentID = studentID.uuidString
        onOlder.createdAt = mastered.addingTimeInterval(-86_400)
        let onNewer = CDLessonPresentation(context: context)
        onNewer.lessonID = try #require(newer.id).uuidString
        onNewer.studentID = studentID.uuidString
        onNewer.createdAt = mastered
        onNewer.masteredAt = mastered
        CoreDataTestHelpers.save(context)

        DataCleanupService.mergeSameNameLessons(using: context)
        CoreDataTestHelpers.save(context)

        let marks = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        #expect(marks.count == 1)
        #expect(marks.first === onOlder)
        #expect(marks.first?.masteredAt == mastered)
    }

    @Test("The launch dedupe pass reports same-name merges under their own key")
    func dedupePassIncludesNameMerge() throws {
        let context = try makeContext()
        seedAreaLesson("Obtuse Angled Triangle", order: 4, in: context)
        seedAreaLesson("Obtuse Angled Triangle", order: 9, in: context)
        CoreDataTestHelpers.save(context)

        let results = DataCleanupService.deduplicateAllModels(using: context)
        #expect(results["Lesson (same name)"] == 1)
        CoreDataTestHelpers.save(context)
        #expect(lessons(in: context).count == 1)
    }

    // MARK: - Creation guard

    @Test("createLesson refuses a name already filed in the same sub-area, case- and accent-insensitively")
    func createRefusesDuplicateName() throws {
        let context = try makeContext()
        let repository = LessonRepository(context: context)
        let first = try repository.createLesson(name: "Right Angled Triangle", area: "Geometry", sequence: "Area")
        CoreDataTestHelpers.save(context)

        #expect(throws: LessonRepository.CreationError.duplicateName(
            existingID: first.id, name: "right angled triangle", area: "Geometry", sequence: "Area"
        )) {
            try repository.createLesson(name: " right angled triangle", area: "Geometry", sequence: "Area")
        }
        #expect(lessons(in: context).count == 1)
    }

    @Test("createLesson allows the same name in another sub-area and for parsha lessons")
    func createAllowsOtherFilings() throws {
        let context = try makeContext()
        let repository = LessonRepository(context: context)
        _ = try repository.createLesson(name: "The Rhombus", area: "Geometry", sequence: "Area")
        _ = try repository.createLesson(
            name: "The Rhombus", area: "Geometry", sequence: "Further Exploration of Equivalence"
        )
        _ = try repository.createLesson(name: "Middle Girls", area: "Parsha", parshaKey: "bereishit")
        _ = try repository.createLesson(name: "Middle Girls", area: "Parsha", parshaKey: "noach")
        CoreDataTestHelpers.save(context)
        #expect(lessons(in: context).count == 4)
    }

    @Test("create_lesson over MCP reports the existing lesson instead of adding a second")
    func mcpCreateLessonStaysIdempotent() async throws {
        let context = try makeContext()
        seedAreaLesson("Rectangle", order: 0, in: context)
        CoreDataTestHelpers.save(context)
        let tools = MCPNotebookTools.makeTools(context: { context })
        let create = try #require(tools.first { $0.name == "create_lesson" })

        let output = try await create.handler([
            "name": .string("rectangle"), "area": .string("Geometry"), "sub_area": .string("Area")
        ])
        #expect(output.contains("Already in the curriculum"))
        #expect(lessons(in: context).count == 1)
    }
}
