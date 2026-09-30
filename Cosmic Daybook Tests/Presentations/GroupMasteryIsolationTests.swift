import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// Logic-break sweep 2026-09-29, B5. The presentation screen shows one mastery
// control for the whole group, loaded as the highest state any child holds.
// Every save wrote that state back to every child, so one child's mastery
// was copied onto classmates whenever the guide saved anything (notes, the
// date). Now the state is written only when the guide changes the control.
@Suite("Group mastery isolation")
@MainActor
struct GroupMasteryIsolationTests {

    private struct Group {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let ada: CDStudent
        let ben: CDStudent
        let assignment: CDLessonAssignment
    }

    /// A lesson given to Ada and Ben on one presentation, with Ada already proficient.
    private func makeGroup() throws -> Group {
        let ctx = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: ctx, name: "Checkerboard")
        lesson.id = UUID()
        let ada = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ada")
        ada.id = UUID()
        let ben = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ben")
        ben.id = UUID()
        let given = AppCalendar.startOfDay(Date().addingTimeInterval(-86_400))
        let assignment = PresentationFactory.makeScheduled(
            lessonID: try #require(lesson.id),
            studentIDs: [try #require(ada.id), try #require(ben.id)],
            scheduledFor: given,
            context: ctx
        )
        assignment.lesson = lesson
        _ = try LifecycleService.recordPresentation(from: assignment, presentedAt: given, modelContext: ctx)
        row(for: ada, lesson: lesson, in: ctx)?.state = .proficient
        #expect(CoreDataTestHelpers.save(ctx))
        return Group(context: ctx, lesson: lesson, ada: ada, ben: ben, assignment: assignment)
    }

    private func row(
        for student: CDStudent, lesson: CDLesson, in ctx: NSManagedObjectContext
    ) -> CDLessonPresentation? {
        let request = PresentationDetailViewModel.presentationsRequest(
            lessonID: lesson.id?.uuidString ?? "", studentIDs: [student.id?.uuidString ?? ""]
        )
        return ctx.safeFetch(request).first
    }

    private func viewModel(for group: Group) -> PresentationDetailViewModel {
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        return PresentationDetailViewModel(
            lessonAssignment: group.assignment, viewContext: group.context, saveCoordinator: coordinator
        )
    }

    private func save(_ viewModel: PresentationDetailViewModel, _ group: Group) {
        viewModel.save(
            studentsAll: [group.ada, group.ben],
            lessons: [group.lesson],
            lessonAssignmentsAll: [group.assignment],
            calendar: AppCalendar.shared
        )
    }

    @Test("Saving without touching the mastery control leaves each child's state as it was")
    func plainSaveKeepsEachChildsState() throws {
        let group = try makeGroup()
        let viewModel = viewModel(for: group)
        #expect(viewModel.proficiencyState == .proficient)

        viewModel.notes = "Worked through the first row together."
        save(viewModel, group)

        #expect(row(for: group.ada, lesson: group.lesson, in: group.context)?.state == .proficient)
        #expect(row(for: group.ben, lesson: group.lesson, in: group.context)?.state == .presented)
        #expect(row(for: group.ben, lesson: group.lesson, in: group.context)?.masteredAt == nil)
    }

    @Test("Changing the mastery control applies the new state to the group")
    func changedControlAppliesToGroup() throws {
        let group = try makeGroup()
        let viewModel = viewModel(for: group)

        viewModel.proficiencyState = .practicing
        save(viewModel, group)

        #expect(row(for: group.ada, lesson: group.lesson, in: group.context)?.state == .practicing)
        #expect(row(for: group.ben, lesson: group.lesson, in: group.context)?.state == .practicing)
    }
}
