import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-03 (fix agent S1), the pieces the fixes added: Readjust
// works out its moves and asks with a count before writing (#31), Add
// Sequence and the recap say in plain words why nothing happened (#32, the
// recap's logged-only failures), and a recap choice made before Record
// reaches the rows the recording makes (#18).
@Suite("Year plan and recap asks (bug hunt fixes 11-03, S1)", .serialized)
@MainActor
struct YearPlanAsksFix1103S1 {
    private typealias Fixture = Fix1103S1Fixture

    // MARK: - #31 Readjust asks with a count

    @Test("#31 Readjust counts its moves and writes nothing until the guide agrees")
    func readjustAsksWithACount() async throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let beads = Fixture.seedSequence([1, 2, 3], in: context)
        let bank = CoreDataTestHelpers.seedLesson(in: context, name: "Bank Game", area: "Math", sequence: "Bank Game")
        // Two sequences fallen behind: three Golden Beads lessons and one Bank Game.
        let entries = [
            Fixture.seedEntry(for: ada, lesson: beads[0], on: Fixture.daysFromToday(-12), order: 1, in: context),
            Fixture.seedEntry(for: ada, lesson: beads[1], on: Fixture.daysFromToday(-9), order: 2, in: context),
            Fixture.seedEntry(for: ada, lesson: beads[2], on: Fixture.daysFromToday(-6), order: 3, in: context),
            Fixture.seedEntry(for: ada, lesson: bank, on: Fixture.daysFromToday(-5), in: context)
        ]
        #expect(CoreDataTestHelpers.save(context))
        let viewModel = StudentYearPlanViewModel()
        viewModel.load(studentID: ada.id, context: context)
        let before = entries.map(\.plannedDate)

        let plan = viewModel.readjustPlan(context: context)
        #expect(plan.lessonCount == 4)
        #expect(plan.sequenceCount == 2)
        #expect(plan.question == "Move 4 lessons in 2 sequences?")
        #expect(plan.actionTitle == "Move Lessons")
        // Asking changed nothing.
        #expect(entries.map(\.plannedDate) == before)
        #expect(!context.hasChanges)

        await viewModel.readjust(plan, studentID: try #require(ada.id), context: context)
        let tomorrow = Fixture.daysFromToday(1)
        #expect(entries.allSatisfy { ($0.plannedDate ?? .distantPast) >= tomorrow })
        #expect(!context.hasChanges)
        // Once re-laid there is nothing left to move.
        #expect(viewModel.readjustPlan(context: context).isEmpty)
    }

    @Test("#31 one move reads in the singular")
    func readjustQuestionSingular() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lesson = try #require(Fixture.seedSequence([1], in: context).first)
        let entry = Fixture.seedEntry(for: ada, lesson: lesson, on: Fixture.daysFromToday(-3), in: context)

        let plan = YearPlanReadjustPlan(moves: [YearPlanPacing.Move(entry: entry, date: Fixture.daysFromToday(2))])
        #expect(plan.question == "Move 1 lesson in 1 sequence?")
        #expect(plan.actionTitle == "Move Lesson")
    }

    // MARK: - #32 and the recap's failures, in plain words

    @Test("#32 Add Sequence says why it planned nothing for a child who has left")
    func addSequenceSaysWhy() async throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Ada", lastName: "Levi", enrollmentStatus: .withdrawn
        )
        let lessons = Fixture.seedSequence([1, 2], in: context)
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = AddSequenceViewModel()
        viewModel.selectedLesson = lessons[0]
        await viewModel.computePreview(student: ada, context: context)
        #expect(!viewModel.scheduleAll(student: ada, context: context))
        #expect(viewModel.refusalMessage == "Ada L has left the class, so they can't get new plans.")
    }

    @Test("the recap's Add Work failure names a child who has left, and says Try again otherwise")
    func recapWorkFailureMessages() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let left = WorkRepository.AssignmentError.studentNotEnrolled(name: "Ada Levi", status: "withdrawn")
        let other = CocoaError(.validationMissingMandatoryProperty)

        #expect(
            PresentationDetailViewModel.recapWorkFailureMessage(for: left, student: ada)
                == "Ada L has left the class, so they can't get new work."
        )
        #expect(
            PresentationDetailViewModel.recapWorkFailureMessage(for: other, student: ada)
                == "Couldn't add the work. Try again."
        )
    }

    // MARK: - #18 A choice made before Record

    @Test("#18 a child marked Mastered on the recap before Record keeps it on the row the recording makes")
    func recapChoiceKeptAfterRecording() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lesson = try #require(Fixture.seedSequence([1], in: context).first)
        let today = Fixture.daysFromToday(0)
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada], scheduledFor: today, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = Fixture.viewModel(for: assignment, in: context)
        viewModel.updateSiblingLessonProficiencyState(
            lessonID: try #require(lesson.id).uuidString,
            studentID: try #require(ada.id).uuidString,
            state: .proficient,
            lessons: [lesson],
            currentLesson: lesson,
            students: [ada]
        )
        _ = try LifecycleService.recordPresentation(from: assignment, presentedAt: today, modelContext: context)
        viewModel.applyRecapStateEditsAfterRecording()

        let rows = Fixture.rows(for: ada, lesson: lesson, in: context)
        #expect(rows.contains { $0.presentationID == assignment.id?.uuidString })
        #expect(!rows.isEmpty && rows.allSatisfy { $0.state == .proficient && $0.masteredAt != nil })
        #expect(!context.hasChanges)
    }
}
