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

    // Active calendar used across computations to ensure consistency
    private var activeCalendar: Calendar = .current

    // Start with a valid empty range; we'll expand it as needed
    private var cachedNonSchoolRange: Range<Date> = Date.distantPast..<Date.distantPast

    // Local cache used during refresh to avoid mutating @Published mid-computation
    private struct NonSchoolCache {
        var days: Set<Date>
        var range: Range<Date>
    }

    // Handle to cancel in-flight refreshes when a new one starts
    private var refreshTask: Task<Void, Never>? = nil

    func refreshNow(calendar: Calendar, context: ModelContext, startDate: Date) {
        // Cancel any in-flight refresh
        refreshTask?.cancel()
        // Start a new refresh task on the main actor (this type is @MainActor)
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh(calendar: calendar, context: context, startDate: startDate)
        }
    }

    func refresh(calendar: Calendar, context: ModelContext, startDate: Date) async {
        // Keep a consistent calendar for all helper computations
        activeCalendar = calendar

        // 1) Build a local cache of non-school days for a window around the start date
        let window = dayRange(around: startDate, bufferDays: 10, calendar: calendar)
        var localCache = NonSchoolCache(
            days: computeNonSchoolDays(in: window, calendar: calendar, context: context),
            range: window
        )

        // Early cancellation check
        if Task.isCancelled { return }

        // 2) Compute 7 school days starting from startDate using the local cache
        let newVisibleDays = computeSchoolDays(
            from: startDate,
            count: 7,
            calendar: calendar,
            context: context,
            cache: &localCache
        )

        // Early cancellation check
        if Task.isCancelled { return }

        // 3) Fetch scheduled lessons for the visible range
        let newScheduledLessons: [StudentLesson]
        if let first = newVisibleDays.first, let last = newVisibleDays.last {
            let lower = calendar.startOfDay(for: first)
            let upper: Date = {
                if let u = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) {
                    return u
                } else {
                    assertionFailure("Calendar failed to add one day when computing upper bound")
                    return lower
                }
            }()
            newScheduledLessons = fetchScheduledLessons(in: lower..<upper, context: context)
        } else {
            newScheduledLessons = []
        }

        // Early cancellation check
        if Task.isCancelled { return }

        // 4) Fetch unscheduled lessons (inbox)
        let newUnscheduledLessons = fetchUnscheduledLessons(context: context)

        // Respect cancellation before mutating published state
        if Task.isCancelled { return }

        // Coalesce UI updates by assigning after all computations complete
        nonSchoolDays = localCache.days
        cachedNonSchoolRange = localCache.range
        visibleDays = newVisibleDays
        scheduledLessonsInRange = newScheduledLessons
        unscheduledLessons = newUnscheduledLessons
    }

    func isNonSchoolDayFast(_ day: Date) -> Bool {
        nonSchoolDays.contains(startOfDay(day))
    }

    // MARK: - Private helpers
    private func startOfDay(_ date: Date) -> Date {
        activeCalendar.startOfDay(for: date)
    }

    private func dayRange(around start: Date, bufferDays: Int, calendar: Calendar) -> Range<Date> {
        let startDay = calendar.startOfDay(for: start)
        let lower: Date = {
            if let d = calendar.date(byAdding: .day, value: -bufferDays, to: startDay) {
                return d
            } else {
                assertionFailure("Calendar failed to subtract days for lower bound")
                return startDay
            }
        }()
        let upper: Date = {
            if let d = calendar.date(byAdding: .day, value: bufferDays + 1, to: startDay) {
                return d
            } else {
                assertionFailure("Calendar failed to add days for upper bound")
                return startDay
            }
        }()
        return lower..<upper
    }

    private func computeSchoolDays(
        from start: Date,
        count: Int,
        calendar: Calendar,
        context: ModelContext,
        cache: inout NonSchoolCache
    ) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let maxLookAheadDays = 365
        var daysSearched = 0
        while result.count < count {
            if daysSearched >= maxLookAheadDays {
                assertionFailure("computeSchoolDays: Searched \(maxLookAheadDays) days without finding \(count) school days. Check SchoolCalendar configuration.")
                break
            }

            // Ensure our non-school-day cache covers the current cursor
            ensureCoverage(cursor, cache: &cache, calendar: calendar, context: context)

            // Prefer cached classification; fall back defensively if needed
            let dayStart = calendar.startOfDay(for: cursor)
            let isNonSchool = cache.days.contains(dayStart) || SchoolCalendar.isNonSchoolDay(cursor, using: context)
            if !isNonSchool { result.append(dayStart) }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                assertionFailure("Calendar failed to add one day while computing school days")
                break
            }
            cursor = calendar.startOfDay(for: next)
            daysSearched += 1
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
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                assertionFailure("Calendar failed to add one day while computing non-school days")
                break
            }
            cursor = calendar.startOfDay(for: next)
        }
        return result
    }

    private func ensureCoverage(_ date: Date, cache: inout NonSchoolCache, calendar: Calendar, context: ModelContext) {
        if !cache.range.contains(date) {
            // Expand cache around the date by a reasonable chunk
            let expansion = dayRange(around: date, bufferDays: 30, calendar: calendar)
            let extra = computeNonSchoolDays(in: expansion, calendar: calendar, context: context)
            cache.days.formUnion(extra)
            let lower = min(cache.range.lowerBound, expansion.lowerBound)
            let upper = max(cache.range.upperBound, expansion.upperBound)
            cache.range = lower..<upper
        }
    }

    private func fetchScheduledLessons(in range: Range<Date>, context: ModelContext) -> [StudentLesson] {
        let predicate = #Predicate<StudentLesson> { sl in
            sl.isPresented == false &&
            sl.givenAt == nil &&
            sl.scheduledFor != nil &&
            (
                (sl.scheduledForDay >= range.lowerBound && sl.scheduledForDay < range.upperBound) ||
                (sl.scheduledFor! >= range.lowerBound && sl.scheduledFor! < range.upperBound)
            )
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
    
    deinit {
        refreshTask?.cancel()
    }
}

