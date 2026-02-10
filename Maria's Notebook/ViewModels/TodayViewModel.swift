// TodayViewModel.swift
// View model powering the Today hub. Fetches lessons, work items, and plan items
// for the selected day. Uses lightweight lookup caches to avoid per-row fetches.
//
// Delegates to:
// - TodayDataFetcher: All database fetch operations
// - TodayScheduleBuilder: Schedule construction from work data
// - TodayNavigationService: School day navigation
// - TodayAttendanceLoader: Attendance processing
// - TodayCacheManager: Student/lesson/work caching
// - TodayTypes: Shared type definitions

import Foundation
import SwiftUI
import SwiftData

/// View model for the Today screen.
/// - Manages date selection and a level filter.
/// - Builds in-memory caches to avoid repeated fetches per row.
@Observable
@MainActor
final class TodayViewModel {

    // MARK: - Type Aliases (for backwards compatibility)

    typealias AttendanceSummary = Maria_s_Notebook.AttendanceSummary
    typealias LevelFilter = Maria_s_Notebook.LevelFilter

    // MARK: - Dependencies

    private let context: ModelContext
    private var calendar: Calendar
    private let cacheManager = TodayCacheManager()

    // MARK: - School Day Cache

    // Use shared SchoolDayCache to avoid repeated database fetches
    private var schoolDayCache = SchoolDayCache()

    // MARK: - Inputs

    var date: Date {
        didSet {
            let normalized = date.startOfDay
            if date != normalized {
                date = normalized
                return
            }
            // Clear recent notes student cache when date changes to prevent unbounded growth
            recentNoteStudentsByID.removeAll(keepingCapacity: true)
            scheduleReload()
        }
    }
    var levelFilter: LevelFilter = .all { didSet { scheduleReload() } }

    // MARK: - Outputs

    var todaysLessons: [StudentLesson] = []

    // WorkModel-based lists
    var overdueSchedule: [ScheduledWorkItem] = []
    var todaysSchedule: [ScheduledWorkItem] = []
    var staleFollowUps: [FollowUpWorkItem] = []

    // Completed work items
    var completedWork: [WorkModel] = []

    // Reminders for today
    var todaysReminders: [Reminder] = []
    var overdueReminders: [Reminder] = []
    var anytimeReminders: [Reminder] = []  // Reminders with no due date

    // Calendar events for today
    var todaysCalendarEvents: [CalendarEvent] = []

    var attendanceSummary: AttendanceSummary = AttendanceSummary()
    var absentToday: [UUID] = []
    var leftEarlyToday: [UUID] = []

    // New Outputs for recent notes and their students
    var recentNotes: [Note] = []
    var recentNoteStudentsByID: [UUID: Student] = [:]

    // MARK: - Cache Accessors (delegate to cacheManager)

    /// Students lookup dictionary (read-only access to cache)
    var studentsByID: [UUID: Student] {
        cacheManager.studentsByID
    }

    /// Lessons lookup dictionary (read-only access to cache)
    var lessonsByID: [UUID: Lesson] {
        cacheManager.lessonsByID
    }

    /// Work lookup dictionary (read-only access to cache)
    var workByID: [UUID: WorkModel] {
        cacheManager.workByID
    }

    /// First names that appear more than once among cached students
    var duplicateFirstNames: Set<String> {
        cacheManager.duplicateFirstNames
    }

    /// Returns the display name for a student ID
    func displayName(for studentID: UUID) -> String {
        cacheManager.displayName(for: studentID)
    }

    /// Returns the lesson name for a lesson ID
    func lessonName(for lessonID: UUID) -> String {
        cacheManager.lessonName(for: lessonID)
    }

    // MARK: - Scheduling

    // ENERGY OPTIMIZATION: Debounce reloads to prevent excessive database queries
    // during rapid changes (e.g., date picker scrolling, filter changes)
    // This warning is a known Swift 6 issue with Task cancellation in deinit
    // The property must be nonisolated(unsafe) to allow cancellation from deinit
    nonisolated(unsafe) private var reloadTask: Task<Void, Never>?

    /// Schedules a debounced reload. Use this for data-driven changes that may happen rapidly.
    /// For user-initiated changes, call reload() directly for immediate feedback.
    func scheduleReload() {
        // Cancel any pending reload
        reloadTask?.cancel()

        // Schedule a debounced reload (400ms delay balances responsiveness with energy efficiency)
        reloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce
                guard !Task.isCancelled else { return }
                reload()
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    // MARK: - Init

    init(context: ModelContext, date: Date = Date(), calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
        AppCalendar.adopt(timeZoneFrom: calendar)
        self.date = date.startOfDay
        scheduleReload()
    }

    nonisolated deinit {
        // Cancel any pending reload task to prevent leaks and unnecessary work
        // reloadTask is marked nonisolated(unsafe) to allow access from deinit
        // This is safe because Task.cancel() is thread-safe.
        reloadTask?.cancel()
    }

    func setCalendar(_ cal: Calendar) {
        self.calendar = cal
        AppCalendar.adopt(timeZoneFrom: cal)
        let normalized = self.date.startOfDay
        if self.date != normalized {
            self.date = normalized
        } else {
            scheduleReload()
        }
    }

    // MARK: - Public API

    func reload() {
        let (day, nextDay) = AppCalendar.dayRange(for: date)

        // PERFORMANCE: Fetch all data first, then batch update @Published properties
        // This reduces view re-renders from 7+ to 1 by coalescing all changes

        // 1. Fetch lessons data
        let lessonsResult = TodayLessonsLoader.fetchLessonsWithIDs(day: day, nextDay: nextDay, context: context)
        if !lessonsResult.lessons.isEmpty {
            cacheManager.loadStudentsIfNeeded(ids: lessonsResult.neededStudentIDs, context: context)
            cacheManager.loadLessonsIfNeeded(ids: lessonsResult.neededLessonIDs, context: context)
        }
        let filteredLessons = lessonsResult.lessons.isEmpty ? [] :
            TodayLevelFilterService.filterLessons(lessonsResult.lessons, studentsByID: studentsByID, levelFilter: levelFilter)

        // 2. Fetch work data
        if let prelimResult = TodayDataFetcher.fetchWorkData(day: day, nextDay: nextDay, referenceDate: date, context: context) {
            cacheManager.loadStudentsIfNeeded(ids: prelimResult.neededStudentIDs, context: context)
            cacheManager.loadLessonsIfNeeded(ids: prelimResult.neededLessonIDs, context: context)
        }
        let workResult = TodayWorkLoader.loadWork(
            day: day, nextDay: nextDay, referenceDate: date,
            studentsByID: studentsByID, levelFilter: levelFilter, context: context
        )
        cacheManager.updateWork(workResult.workByID)

        // 3. Fetch completed work
        let completedResult = TodayWorkLoader.fetchCompletedWork(day: day, nextDay: nextDay, context: context)
        cacheManager.loadStudentsIfNeeded(ids: completedResult.neededStudentIDs, context: context)
        let filteredCompletedWork = TodayLevelFilterService.filterWork(
            completedResult.completedWork, studentsByID: studentsByID, levelFilter: levelFilter
        )

        // 4. Fetch reminders
        let remindersResult = TodayDataFetcher.fetchReminders(day: day, nextDay: nextDay, context: context)

        // 5. Fetch calendar events
        let calendarEvents = TodayDataFetcher.fetchCalendarEvents(day: day, nextDay: nextDay, context: context)

        // 6. Fetch attendance
        let attendanceResult = TodayDataFetcher.fetchAttendance(day: day, nextDay: nextDay, context: context)
        cacheManager.loadStudentsIfNeeded(ids: attendanceResult.neededStudentIDs, context: context)
        let processedAttendance = TodayAttendanceLoader.processAttendance(
            records: attendanceResult.records, studentsByID: studentsByID, levelFilter: levelFilter
        )

        // 7. Fetch recent notes
        let notesResult = TodayDataFetcher.fetchRecentNotes(context: context)
        let missingStudentIDs = notesResult.neededStudentIDs.subtracting(recentNoteStudentsByID.keys)
        var updatedRecentNoteStudents = recentNoteStudentsByID
        
        // PERFORMANCE: Batch fetch all missing students in a single query instead of N queries
        if !missingStudentIDs.isEmpty {
            let allStudents = context.safeFetch(FetchDescriptor<Student>())
            let missingStudents = allStudents.filter { missingStudentIDs.contains($0.id) }
            for student in missingStudents {
                updatedRecentNoteStudents[student.id] = student
            }
        }

        // BATCH UPDATE: Apply all @Published changes together to minimize view re-renders
        todaysLessons = filteredLessons
        overdueSchedule = workResult.overdueSchedule
        todaysSchedule = workResult.todaysSchedule
        staleFollowUps = workResult.staleFollowUps
        completedWork = filteredCompletedWork
        overdueReminders = remindersResult.overdue
        todaysReminders = remindersResult.today
        anytimeReminders = remindersResult.anytime
        todaysCalendarEvents = calendarEvents
        attendanceSummary = processedAttendance.summary
        absentToday = processedAttendance.absentStudentIDs
        leftEarlyToday = processedAttendance.leftEarlyStudentIDs
        recentNotes = notesResult.notes
        recentNoteStudentsByID = updatedRecentNoteStudents
    }

    // MARK: - School Day Navigation (delegated to TodayNavigationService)

    /// Finds the next day (after the given date) that has lessons scheduled.
    /// Only considers school days and respects the current level filter.
    func nextDayWithLessons(after date: Date) -> Date {
        TodayNavigationService.nextDayWithLessons(
            after: date,
            levelFilter: levelFilter,
            cache: &schoolDayCache,
            context: context
        )
    }

    /// Finds the previous day (before the given date) that has lessons scheduled.
    /// Only considers school days and respects the current level filter.
    func previousDayWithLessons(before date: Date) -> Date {
        TodayNavigationService.previousDayWithLessons(
            before: date,
            levelFilter: levelFilter,
            cache: &schoolDayCache,
            context: context
        )
    }

}

// MARK: - Equatable Conformance

extension TodayViewModel: Equatable {
    /// Compare only properties that affect UI rendering
    /// This allows SwiftUI to skip re-rendering when nothing visual has changed
    ///
    /// FUTURE OPTIMIZATION: For even more granular control, individual view sections
    /// could use `withObservationTracking` to track only specific properties they access.
    /// This would enable per-section updates instead of whole-view updates.
    /// Example:
    /// ```swift
    /// withObservationTracking {
    ///     ForEach(viewModel.todaysLessons) { lesson in
    ///         LessonRow(lesson: lesson)
    ///     }
    /// } onChange: {
    ///     // View updates only when todaysLessons changes, not when reminders change
    /// }
    /// ```
    static func == (lhs: TodayViewModel, rhs: TodayViewModel) -> Bool {
        // Compare inputs that trigger reloads
        guard lhs.date == rhs.date,
              lhs.levelFilter == rhs.levelFilter else {
            return false
        }
        
        // Compare output arrays by count and IDs (not full equality to avoid deep comparison)
        guard lhs.todaysLessons.count == rhs.todaysLessons.count,
              lhs.todaysLessons.map(\.id) == rhs.todaysLessons.map(\.id),
              
              lhs.overdueSchedule.count == rhs.overdueSchedule.count,
              lhs.todaysSchedule.count == rhs.todaysSchedule.count,
              lhs.staleFollowUps.count == rhs.staleFollowUps.count,
              
              lhs.completedWork.count == rhs.completedWork.count,
              lhs.completedWork.map(\.id) == rhs.completedWork.map(\.id),
              
              lhs.todaysReminders.count == rhs.todaysReminders.count,
              lhs.todaysReminders.map(\.id) == rhs.todaysReminders.map(\.id),
              lhs.overdueReminders.count == rhs.overdueReminders.count,
              lhs.anytimeReminders.count == rhs.anytimeReminders.count,
              
              lhs.todaysCalendarEvents.count == rhs.todaysCalendarEvents.count,
              lhs.todaysCalendarEvents.map(\.id) == rhs.todaysCalendarEvents.map(\.id),
              
              lhs.recentNotes.count == rhs.recentNotes.count,
              lhs.recentNotes.map(\.id) == rhs.recentNotes.map(\.id) else {
            return false
        }
        
        // Compare attendance summary
        guard lhs.attendanceSummary == rhs.attendanceSummary,
              lhs.absentToday == rhs.absentToday,
              lhs.leftEarlyToday == rhs.leftEarlyToday else {
            return false
        }
        
        // Don't compare cache internals (studentsByID, lessonsByID, workByID, etc.)
        // as they don't directly affect rendering
        
        return true
    }
}
