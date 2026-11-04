import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-03, the sequence recap on the presentation sheet (fix agent
// S1): the current lesson's row marks one child (#18), and a regive keeps
// Mastered and the first dates (#22).
@Suite("Sequence recap (bug hunt fixes 11-03, S1)", .serialized)
@MainActor
struct SequenceRecapFix1103S1 {
    private typealias Fixture = Fix1103S1Fixture

    // MARK: - #18 The recap's current lesson

    @Test("#18 the current lesson's picker marks one child Mastered, and Save keeps it on every row she has")
    func currentRowPickerWritesHerRows() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Cohen")
        let lesson = try #require(Fixture.seedSequence([1], in: context).first)
        let givenDay = Fixture.daysFromToday(-1)
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada], scheduledFor: givenDay, context: context
        )
        _ = try LifecycleService.recordPresentation(from: assignment, presentedAt: givenDay, modelContext: context)
        #expect(CoreDataTestHelpers.save(context))

        // Ben was there too: the guide adds him on the sheet, opens his row for
        // this lesson in the recap and marks him Mastered, then saves.
        let vm = Fixture.viewModel(for: assignment, in: context)
        vm.selectedStudentIDs.insert(try #require(ben.id))
        vm.updateSiblingLessonProficiencyState(
            lessonID: try #require(lesson.id).uuidString,
            studentID: try #require(ben.id).uuidString,
            state: .proficient,
            lessons: [lesson],
            currentLesson: lesson,
            students: [ada, ben]
        )
        vm.save(
            studentsAll: [ada, ben], lessons: [lesson], lessonAssignmentsAll: [assignment],
            calendar: AppCalendar.shared
        )

        let benRows = Fixture.rows(for: ben, lesson: lesson, in: context)
        #expect(benRows.contains { $0.presentationID == assignment.id?.uuidString })
        #expect(!benRows.isEmpty && benRows.allSatisfy { $0.state == .proficient && $0.masteredAt != nil })
        // Her classmate keeps his own state: nothing is copied across the group.
        let adaRows = Fixture.rows(for: ada, lesson: lesson, in: context)
        #expect(!adaRows.isEmpty && adaRows.allSatisfy { $0.state == .presented && $0.masteredAt == nil })
    }

    @Test("#18 on a plan not yet given, the current lesson's picker writes nothing until Record, but shows the choice")
    func currentRowPickerWaitsOnAPlan() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lesson = try #require(Fixture.seedSequence([1], in: context).first)
        let plan = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada], scheduledFor: Fixture.daysFromToday(2), context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let vm = Fixture.viewModel(for: plan, in: context)
        vm.updateSiblingLessonProficiencyState(
            lessonID: try #require(lesson.id).uuidString,
            studentID: try #require(ada.id).uuidString,
            state: .proficient,
            lessons: [lesson],
            currentLesson: lesson,
            students: [ada]
        )

        // No history row: she hasn't been given it, so nothing may read as given today.
        #expect(Fixture.rows(for: ada, lesson: lesson, in: context).isEmpty)
        let entry = try #require(vm.groupRecap?.studentEntries.first?.lessonEntries.first { $0.id == lesson.id })
        #expect(entry.outcomeState == .proficient)
    }

    // MARK: - #22 A regive keeps Mastered

    @Test("#22 a lesson mastered and then given again still reads Mastered, with the first dates")
    func regiveKeepsMasteredAndEarliestDates() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lesson = try #require(Fixture.seedSequence([1], in: context).first)
        let firstDay = Fixture.daysFromToday(-10)
        let masteredDay = Fixture.daysFromToday(-8)
        let regiveDay = Fixture.daysFromToday(-2)

        let first = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada], scheduledFor: firstDay, context: context
        )
        let firstRow = try LifecycleService.upsertLessonPresentation(
            presentationID: try #require(first.id).uuidString,
            studentID: try #require(ada.id).uuidString,
            lessonID: try #require(lesson.id).uuidString,
            presentedAt: firstDay,
            context: context
        )
        first.markPresented(at: firstDay)
        // Marked Mastered two days later (the Checklist's or the recap's mark).
        firstRow.state = .proficient
        firstRow.masteredAt = masteredDay
        firstRow.lastObservedAt = masteredDay

        // A review regive a week on makes a second, newer row.
        let regive = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada], scheduledFor: regiveDay, context: context
        )
        _ = try LifecycleService.upsertLessonPresentation(
            presentationID: try #require(regive.id).uuidString,
            studentID: try #require(ada.id).uuidString,
            lessonID: try #require(lesson.id).uuidString,
            presentedAt: regiveDay,
            context: context
        )
        regive.markPresented(at: regiveDay)
        #expect(CoreDataTestHelpers.save(context))

        let recap = try #require(SequenceRecapResolver.resolve(
            currentLesson: lesson, students: [ada], context: context
        ))
        let student = try #require(recap.studentEntries.first)
        let entry = try #require(student.lessonEntries.first { $0.id == lesson.id })
        #expect(entry.outcomeState == .proficient)
        #expect(entry.masteredAt == masteredDay)
        #expect(entry.firstPresentedAt == firstDay)
        #expect(entry.lastObservedAt == regiveDay)
    }
}
