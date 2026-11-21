import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Two children and a two-lesson sequence, for the domain logic Phase 4 tests
/// (review 2026-11-20: R2, R3, R6, R10, R12, R24).
@MainActor
struct PresentingRoom {
    let context: NSManagedObjectContext
    let coordinator: SaveCoordinator
    let ada: CDStudent
    let ben: CDStudent
    let first: CDLesson
    let second: CDLesson

    var adaID: UUID { ada.id! }
    var benID: UUID { ben.id! }

    static func make() throws -> PresentingRoom {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Test")
        let first = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads: Addition", area: "Math", sequence: "Decimal System"
        )
        first.orderInSequence = 1
        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads: Subtraction", area: "Math", sequence: "Decimal System"
        )
        second.orderInSequence = 2
        try context.save()
        return PresentingRoom(
            context: context, coordinator: coordinator, ada: ada, ben: ben, first: first, second: second
        )
    }

    func day(_ iso: String) throws -> Date {
        try CoreDataTestHelpers.day(iso)
    }

    func rows(_ student: CDStudent, _ lesson: CDLesson) -> [CDLessonPresentation] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND lessonID == %@", student.id!.uuidString, lesson.id!.uuidString
        )
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    func works(_ student: CDStudent, _ lesson: CDLesson) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lesson.id!.uuidString)
        return context.safeFetch(request).filter { !$0.isDeleted && WorkGrouping.owner(of: $0) == student.id }
    }

    func assignments(_ lesson: CDLesson) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lesson.id!.uuidString)
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    /// A recorded presentation of `lesson` for `students` on `iso`.
    @discardableResult
    func given(_ lesson: CDLesson, to students: [CDStudent], on iso: String) throws -> CDLessonAssignment {
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: students, context: context)
        _ = try LifecycleService.recordPresentation(from: assignment, presentedAt: try day(iso), modelContext: context)
        return assignment
    }

    /// Ada given the first lesson twice (two presentations, two history rows),
    /// with open practice work from the later one. Returns the later presentation.
    @discardableResult
    func givenTwiceWithOpenWork() throws -> CDLessonAssignment {
        try given(first, to: [ada], on: "2026-10-05")
        let later = try given(first, to: [ada], on: "2026-10-20")
        _ = try WorkRepository(context: context).createWork(
            studentID: adaID, lessonID: first.id!, kind: .practiceLesson,
            presentationID: later.id, saveImmediately: false
        )
        try context.save()
        #expect(rows(ada, first).count == 2)
        return later
    }

    func checklist() -> ClassAreaChecklistViewModel {
        let viewModel = ClassAreaChecklistViewModel()
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return viewModel
    }

    func tool(_ name: String) throws -> MCPToolDefinition {
        let context = self.context
        return try #require(MCPNotebookTools.makeTools(context: { context }).first { $0.name == name })
    }
}
