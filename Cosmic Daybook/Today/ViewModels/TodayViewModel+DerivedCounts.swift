// TodayViewModel+DerivedCounts.swift
// The count behind Today's "Needs Lesson" card, kept between appearances and
// recomputed only when something it reads has moved.
//
// The count reads a year of presented assignments and walks the school
// calendar once per child, so doing it on every return to Today (and on every
// date step) was the most expensive thing an appearance did. Its inputs are
// the roster, the lessons (the Parsha exclusion), the presented assignments,
// the school calendar, the day, the counter epoch, the hidden test names and
// the one-year window's lower edge; a change to any of them recomputes it.

import CoreData
import Foundation

extension TodayViewModel {

    /// The entities the count reads: the enrolled roster, the lessons (for the
    /// Parsha exclusion), the presented assignments, and the school calendar
    /// the day count walks.
    nonisolated static let derivedCountInputEntities: Set<String> = [
        "Student", "Lesson", "LessonAssignment", "NonSchoolDay", "SchoolDayOverride"
    ]

    /// The inputs the count reads besides its entities.
    struct DerivedCountsStamp: Equatable {
        /// School days are counted up to the start of today.
        let day: Date
        /// The calendar the one-year window is measured in.
        let calendar: Calendar
        /// The counter epoch the day counts clamp to.
        let epoch: Date?
        /// Bumped whenever school-day data changes (or its cache is dropped).
        let schoolDayVersion: Int
        /// The test-student names the roster hides.
        let hiddenNames: Set<String>

        init(calendar: Calendar, now: Date) {
            day = AppCalendar.startOfDay(now)
            self.calendar = calendar
            epoch = SchoolYearCounters.epoch
            schoolDayVersion = SchoolDayDataVersion.current
            hiddenNames = TestStudentsFilter.normalizedHiddenNames()
        }
    }

    /// What a computed count stands on.
    struct DerivedCountsBasis {
        let stamp: DerivedCountsStamp
        /// `createdAt` of the oldest presented assignment in the one-year
        /// window when the count was taken (nil when the window was empty).
        /// Time only ever moves rows out of the window, and this one leaves
        /// first; until it does, the window holds the same rows.
        let windowFloor: Date?
    }

    /// Recomputes `needsLessonCount` when something it reads has moved since
    /// the last computation — an edit to one of its entities, a new day, the
    /// counter epoch, the school calendar, the hidden test names, or an
    /// assignment ageing out of the one-year window — or when `force`.
    func reloadDerivedCountsIfNeeded(calendar: Calendar, now: Date = Date(), force: Bool = false) {
        let inputsMoved = derivedCountFlag().consume(pendingIn: context)
        let stamp = DerivedCountsStamp(calendar: calendar, now: now)
        if !force, !inputsMoved, let basis = derivedCountsBasis, basis.stamp == stamp,
           !Self.windowHasMoved(past: basis.windowFloor, calendar: calendar, now: now) {
            return
        }
        derivedCountsBuildCount += 1
        // Taken before the count, whose own window starts a moment later: the
        // floor can only be earlier than the rows it read, never later.
        let floor = Self.presentedWindowFloor(calendar: calendar, now: now, in: context)
        let count = Self.computeNeedsLessonCount(in: context, calendar: calendar)
        derivedCountsBasis = DerivedCountsBasis(stamp: stamp, windowFloor: floor)
        if count != needsLessonCount { needsLessonCount = count }
    }

    /// Children overdue for a lesson: enrolled, visible, and either never
    /// presented one or seven or more school days since the last. Exactly the
    /// computation TodayView ran on every appearance.
    static func computeNeedsLessonCount(in context: NSManagedObjectContext, calendar: Calendar) -> Int {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        let students = TestStudentsFilter.filterVisible(context.safeFetch(request)).uniqueByID
        guard !students.isEmpty else { return 0 }
        let daysMap = StudentsViewModel().computeDaysSinceLastLessonCache(
            for: students,
            using: context,
            calendar: calendar
        )
        // Never presented (-1) or overdue (>= 7 school days).
        return daysMap.values.filter { $0 == -1 || $0 >= 7 }.count
    }

    /// The start of the one-year window `computeDaysSinceLastLessonCache`
    /// reads, computed the way it computes it.
    nonisolated static func presentedWindowStart(calendar: Calendar, now: Date) -> Date {
        calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 3600)
    }

    /// True once the window's start has passed `floor`, the oldest assignment
    /// the last count read.
    nonisolated static func windowHasMoved(past floor: Date?, calendar: Calendar, now: Date) -> Bool {
        guard let floor else { return false }
        return presentedWindowStart(calendar: calendar, now: now) > floor
    }

    /// `createdAt` of the oldest presented assignment in the window at `now`.
    static func presentedWindowFloor(
        calendar: Calendar, now: Date, in context: NSManagedObjectContext
    ) -> Date? {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "createdAt >= %@ AND stateRaw == %@",
            presentedWindowStart(calendar: calendar, now: now) as CVarArg,
            LessonAssignmentState.presented.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.fetchLimit = 1
        return context.safeFetch(request).first?.createdAt
    }

    private func derivedCountFlag() -> ManagedObjectChangeFlag {
        if let existing = derivedCountInputs { return existing }
        let flag = ManagedObjectChangeFlag(entityNames: Self.derivedCountInputEntities, context: context)
        derivedCountInputs = flag
        return flag
    }
}
