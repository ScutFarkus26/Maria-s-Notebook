import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Notebook Companion")
@MainActor
final class NotebookCompanionTests {

    @Test("Working and attention states take precedence over celebration")
    func statePrecedence() {
        let snapshot = NotebookCompanionSnapshot(
            overdueTodoCount: 2,
            dueTodayTodoCount: 1,
            overduePresentationCount: 1,
            scheduledPresentationCount: 2,
            recordedActivityCount: 4
        )

        #expect(snapshot.state(isWorking: true) == .working)
        #expect(snapshot.state(isWorking: false) == .attention)
        #expect(snapshot.attentionCount == 3)
        #expect(snapshot.headline(isWorking: false) == "1 missed presentation needs a decision.")
    }

    @Test("A calm companion celebrates recorded activity")
    func accomplishmentState() {
        let snapshot = NotebookCompanionSnapshot(recordedActivityCount: 3)

        #expect(snapshot.state(isWorking: false) == .accomplished)
        #expect(snapshot.headline(isWorking: false) == "You've recorded 3 updates today.")
    }

    @Test("The day briefing includes the visible counts")
    func briefingIncludesCounts() {
        let snapshot = NotebookCompanionSnapshot(
            overdueTodoCount: 2,
            dueTodayTodoCount: 3,
            overduePresentationCount: 1,
            scheduledPresentationCount: 4
        )

        #expect(snapshot.briefingPrompt.contains("2 overdue todos"))
        #expect(snapshot.briefingPrompt.contains("1 missed presentations"))
        #expect(snapshot.briefingPrompt.contains("3 todos due today"))
        #expect(snapshot.briefingPrompt.contains("4 presentations scheduled today"))
    }

    @Test("The view model counts only the selected calendar day")
    func viewModelBuildsTodaySnapshot() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 10,
            hour: 12
        ))!
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let overdueTodo = CDTodoItem(context: context)
        overdueTodo.title = "Overdue"
        overdueTodo.dueDate = yesterday

        let todayTodo = CDTodoItem(context: context)
        todayTodo.title = "Today"
        todayTodo.dueDate = calendar.date(byAdding: .hour, value: 9, to: today)

        let futureTodo = CDTodoItem(context: context)
        futureTodo.title = "Future"
        futureTodo.dueDate = tomorrow

        let missedPresentation = CDLessonAssignment(context: context)
        missedPresentation.lessonID = UUID().uuidString
        missedPresentation.schedule(for: yesterday, using: calendar)

        let todayPresentation = CDLessonAssignment(context: context)
        todayPresentation.lessonID = UUID().uuidString
        todayPresentation.schedule(for: today, using: calendar)

        let completedWork = CoreDataTestHelpers.seedWorkModel(in: context)
        completedWork.completedAt = now

        let note = CoreDataTestHelpers.seedNote(in: context)
        note.createdAt = now

        #expect(CoreDataTestHelpers.save(context))

        let viewModel = NotebookCompanionViewModel()
        viewModel.configure(context: context)
        viewModel.reload(now: now, calendar: calendar)

        #expect(viewModel.snapshot.overdueTodoCount == 1)
        #expect(viewModel.snapshot.dueTodayTodoCount == 1)
        #expect(viewModel.snapshot.overduePresentationCount == 1)
        #expect(viewModel.snapshot.scheduledPresentationCount == 1)
        #expect(viewModel.snapshot.recordedActivityCount == 2)
    }
}
