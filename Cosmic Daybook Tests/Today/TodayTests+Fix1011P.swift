import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, Today.
// - #70: Today dropped a todo whose planned day had passed, which the Todos
//   screen's Today list shows (10-10 #25); the two now use one rule.
// - #71: lessons past the first thousand read "Lesson".
// - #77: the Parent Reports banner counted a report twice when sync left two
//   copies, and counted children who have left.

@Suite("Today (Fix1011P)")
@MainActor
struct TodayTests {

    // MARK: - #70

    @Test("Today lists exactly the todos the Todos screen's Today list shows, plus high priority")
    func todosMatchTheTodosScreen() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let day = try CoreDataTestHelpers.day("2026-10-14")
        let at = { (offset: Int) in AppCalendar.addingDays(offset, to: day).addingTimeInterval(9 * 3600) }
        func todo(_ title: String, due: Int? = nil, scheduled: Int? = nil) {
            let item = CDTodoItem(context: context)
            item.title = title
            item.dueDate = due.map(at)
            item.scheduledDate = scheduled.map(at)
        }
        todo("Planned yesterday, not done", scheduled: -1)
        todo("Planned last week, not done", scheduled: -7)
        todo("Planned today", scheduled: 0)
        todo("Planned tomorrow", scheduled: 1)
        todo("Due today", due: 0)
        todo("Due today, planned later", due: 0, scheduled: 3)
        todo("Overdue", due: -2)
        todo("Overdue, rescheduled later", due: -2, scheduled: 2)
        todo("Due next week", due: 7)
        todo("Undated")
        #expect(CoreDataTestHelpers.save(context))

        let all = context.safeFetch(CDFetchRequest(CDTodoItem.self))
        let partition = TodayTodosSectionView<EmptyView>.partition(all, date: day, calendar: AppCalendar.shared)
        let shown = Set(partition.all.map(\.title))
        let todosScreen = Set(all.filter { TodoListFilter.today.matches($0, today: day) }.map(\.title))
        #expect(shown == todosScreen)
        #expect(shown.contains("Planned yesterday, not done"))

        // Each shown todo lands in exactly one group.
        let grouped = partition.overdue.count + partition.dueOnDay.count + partition.highPriority.count
        #expect(grouped == partition.all.count)
    }

    // MARK: - #71

    @Test("Lesson names resolve past the first thousand lessons")
    func lessonNamesPastAThousand() throws {
        let context = try CoreDataTestHelpers.makeContext()
        var ids: [UUID] = []
        for index in 0..<1_050 {
            let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Lesson \(index)")
            ids.append(try #require(lesson.id))
        }
        #expect(CoreDataTestHelpers.save(context))

        let cache = TodayCacheManager()
        cache.loadLessonsIfNeeded(ids: Set(ids), context: context)
        let unnamed = ids.filter { cache.lessonName(for: $0) == "Lesson" }
        #expect(unnamed.isEmpty, "\(unnamed.count) lesson(s) read \"Lesson\"")
    }

    // MARK: - #77 Parent Reports banner

    @Test("The banner counts each child with a sent report once, and only children still here")
    func bannerCountsChildrenOnce() {
        let here = ["A", "B", "C"]
        let sent = ["A", "A", "B", "GONE"]
        #expect(ParentReportsSectionView.sentCount(sentReportStudentIDs: sent, studentIDs: Set(here)) == 2)
        #expect(ParentReportsSectionView.sentCount(sentReportStudentIDs: [], studentIDs: Set(here)) == 0)
    }
}
