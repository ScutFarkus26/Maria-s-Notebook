import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What the 2026-11-03 S1 fix tests (`SequenceRecapFix1103S1`,
/// `YearPlanFix1103S1`) build on: a classroom in memory, one sequence of
/// lessons, year-plan entries and the children's history rows.
@MainActor
enum Fix1103S1Fixture {

    static func makeContext() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        SchoolCalendarService.shared.invalidateCache()
        return context
    }

    static func daysFromToday(_ days: Int) -> Date {
        AppCalendar.addingDays(days, to: AppCalendar.startOfDay(Date()))
    }

    static func viewModel(
        for assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) -> PresentationDetailViewModel {
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        return PresentationDetailViewModel(
            lessonAssignment: assignment, viewContext: context, saveCoordinator: coordinator
        )
    }

    /// Lessons `orders` in one sequence, in that order.
    static func seedSequence(_ orders: [Int64], in context: NSManagedObjectContext) -> [CDLesson] {
        orders.map { order in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Golden Beads \(order)", area: "Math", sequence: "Golden Beads"
            )
            lesson.orderInSequence = order
            return lesson
        }
    }

    @discardableResult
    static func seedEntry(
        for student: CDStudent,
        lesson: CDLesson,
        on date: Date,
        order: Int64 = 0,
        in context: NSManagedObjectContext
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = date
        entry.spacingSchoolDays = 3
        entry.sequenceGroupKey = "\(lesson.area)::\(lesson.sequence)"
        entry.orderInSequence = order
        entry.status = .planned
        return entry
    }

    /// Every history row she has for the lesson.
    static func rows(
        for student: CDStudent, lesson: CDLesson, in context: NSManagedObjectContext
    ) -> [CDLessonPresentation] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND lessonID == %@",
            student.id?.uuidString ?? "", lesson.id?.uuidString ?? ""
        )
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    static func entries(for student: CDStudent, in context: NSManagedObjectContext) -> [CDYearPlanEntry] {
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(format: "studentID == %@", student.id?.uuidString ?? "")
        return context.safeFetch(request)
    }
}
