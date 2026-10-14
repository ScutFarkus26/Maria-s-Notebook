import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Finished (2026-10-13): the status that closes work where mastery doesn't
/// apply. It is the old Done (raw `"complete"`) renamed and offered in every
/// picker, so it closes through the same log as Mastered and is never mastery.
@Suite("Work log service, Finished")
@MainActor
struct WorkLogServiceFinishedTests {

    @Test("Finished closes the work as Mastered does, and marks nothing mastered")
    func finishedClosesWithoutMastery() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let today = AppCalendar.startOfDay(Date())
        let studentID = UUID()
        let lessonID = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Coin three-part cards", studentID: studentID, lessonID: lessonID
        )
        work.kind = .practiceLesson
        let workID = try #require(work.id)
        let todays = CDWorkCheckIn.make(for: work, on: today, purpose: "progressCheck", in: context)
        let later = CDWorkCheckIn.make(for: work, on: AppCalendar.addingDays(7, to: today), in: context)
        let todo = CDTodoItem(context: context)
        todo.title = "Check her coin cards"
        todo.linkedWorkItemID = workID.uuidString
        // The lesson is on her record, presented and not mastered.
        let mark = CDLessonPresentation(context: context)
        mark.studentID = studentID.uuidString
        mark.lessonID = lessonID.uuidString
        mark.presentedAt = AppCalendar.addingDays(-7, to: today)
        #expect(CoreDataTestHelpers.save(context))

        let receipt = try WorkLogService.log([.init(work: work, status: .done)], on: today, context: context)

        #expect(work.status == .done)
        #expect(work.statusRaw == "complete", "Finished stores the raw value every build already knows")
        #expect(work.status.displayName == "Finished")
        #expect(work.completedAt == today)
        #expect(todays.status == .completed)
        #expect(later.status == .skipped)
        #expect(todo.isCompleted)
        #expect(receipt.closed == 1)
        let records = try WorkCompletionService.records(for: workID, in: context)
        #expect(records.map(\.studentID) == [studentID.uuidString])
        // Not mastery: the lesson's mark is untouched, her record reads no
        // mastery for the lesson, and the ladder reads Reviewing.
        #expect(mark.masteredAt == nil)
        #expect(mark.stateRaw == LessonPresentationState.presented.rawValue)
        let marks = PresentationRecordIndex.masteryMarks(lessonIDs: [lessonID.uuidString], in: context)
        let isMastered = marks[lessonID.uuidString]?.contains(studentID.uuidString) ?? false
        #expect(!isMastered)
        #expect(LessonNodeStatus.resolve(
            isPresented: true, scheduledFor: nil, isMastered: isMastered, workStatuses: [work.status]
        ) == .reviewing)
    }

    @Test("Finished is offered in every picker, beside Mastered")
    func finishedIsPickable() {
        #expect(WorkStatus.pickable == [.active, .review, .mastered, .done, .keepPracticing, .incomplete])
        #expect(WorkStatus.done.isClosed)
    }
}
