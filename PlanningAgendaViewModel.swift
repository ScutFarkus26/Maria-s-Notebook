import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class PlanningAgendaViewModel: ObservableObject {
    @Published private(set) var visibleDays: [Date] = []
    @Published private(set) var nonSchoolDays: Set<Date> = []
    @Published private(set) var scheduledLessonsInRange: [StudentLesson] = []
    @Published private(set) var unscheduledLessons: [StudentLesson] = []

    func refresh(calendar: Calendar, context: ModelContext, startDate: Date) async {
        // 1) Build a cache of non-school days for a window around the start date
        let window = dayRange(around: startDate, bufferDays: 10, calendar: calendar)
        nonSchoolDays = computeNonSchoolDays(in: window, calendar: calendar, context: context)

        // 2) Compute 7 school days starting from startDate
        visibleDays = computeSchoolDays(from: startDate, count: 7, calendar: calendar)

        // 3) Fetch scheduled lessons for the visible range
        if let first = visibleDays.first, let last = visibleDays.last {
            let lower = calendar.startOfDay(for: first)
            let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? lower
            scheduledLessonsInRange = fetchScheduledLessons(in: lower..<upper, context: context)
        } else {
            scheduledLessonsInRange = []
        }

        // 4) Fetch unscheduled lessons (inbox)
        unscheduledLessons = fetchUnscheduledLessons(context: context)
    }

    func isNonSchoolDayFast(_ day: Date) -> Bool {
        nonSchoolDays.contains(startOfDay(day))
    }

    // MARK: - Private helpers
    private func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    private func dayRange(around start: Date, bufferDays: Int, calendar: Calendar) -> Range<Date> {
        let startDay = calendar.startOfDay(for: start)
        let lower = calendar.date(byAdding: .day, value: -bufferDays, to: startDay) ?? startDay
        let upper = calendar.date(byAdding: .day, value: bufferDays + 1, to: startDay) ?? startDay
        return lower..<upper
    }

    private func computeSchoolDays(from start: Date, count: Int, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        while result.count < count {
            if !isNonSchoolDayFast(cursor) { result.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return result
    }

    private func computeNonSchoolDays(in range: Range<Date>, calendar: Calendar, context: ModelContext) -> Set<Date> {
        var result: Set<Date> = []
        var cursor = calendar.startOfDay(for: range.lowerBound)
        while cursor < range.upperBound {
            if SchoolCalendar.isNonSchoolDay(cursor, using: context) {
                result.insert(cursor)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            cursor = calendar.startOfDay(for: cursor)
        }
        return result
    }

    private func fetchScheduledLessons(in range: Range<Date>, context: ModelContext) -> [StudentLesson] {
        let predicate = #Predicate<StudentLesson> { sl in
            sl.isPresented == false &&
            sl.givenAt == nil &&
            sl.scheduledFor != nil &&
            sl.scheduledFor! >= range.lowerBound &&
            sl.scheduledFor! < range.upperBound
        }
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.scheduledFor, order: .forward)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }

    private func fetchUnscheduledLessons(context: ModelContext) -> [StudentLesson] {
        let predicate = #Predicate<StudentLesson> { sl in
            sl.isPresented == false &&
            sl.givenAt == nil &&
            sl.scheduledFor == nil
        }
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }
}
