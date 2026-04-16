// TodayViewModel.swift
// View model powering the Today hub. Fetches lessons, work items, and plan items
// for the selected day. Uses lightweight lookup caches to avoid per-row fetches.
//
// Delegates to:
// - TodayDataFetcher: All database fetch operations
// - TodayScheduleBuilder: Schedule construction from work data
// - TodayNavigationService: School day navigation
// - TodayAttendanceLoader: Attendance processing
// - TodayCacheManager: CDStudent/lesson/work caching
// - TodayTypes: Shared type definitions

import Foundation
import SwiftUI
import CoreData

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

    private let context: NSManagedObjectContext
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

    var todaysLessons: [CDLessonAssignment] = []

    // CDWorkModel-based lists
    var overdueSchedule: [ScheduledWorkItem] = []
    var todaysSchedule: [ScheduledWorkItem] = []
    var staleFollowUps: [FollowUpWorkItem] = []

    // Unified agenda (lessons + work items, user-orderable)
    var agendaItems: [AgendaItem] = []

    // Completed work items
    var completedWork: [CDWorkModel] = []

    // Reminders for today
    var todaysReminders: [CDReminder] = []
    var overdueReminders: [CDReminder] = []
    var anytimeReminders: [CDReminder] = []  // Reminders with no due date

    // Calendar events for today
    var todaysCalendarEvents: [CDCalendarEvent] = []

    // Scheduled meetings for today
    var scheduledMeetings: [CDScheduledMeeting] = []

    // Completed meetings for today
    var completedMeetings: [CDStudentMeeting] = []

    var attendanceSummary: AttendanceSummary = AttendanceSummary()
    var absentToday: [UUID] = []
    var leftEarlyToday: [UUID] = []

    // New Outputs for recent notes and their students
    var recentNotes: [CDNote] = []
    var recentNoteStudentsByID: [UUID: CDStudent] = [:]

    // MARK: - Cache Accessors (delegate to cacheManager)

    /// Students lookup dictionary (read-only access to cache)
    var studentsByID: [UUID: CDStudent] {
        cacheManager.studentsByID
    }

    /// Lessons lookup dictionary (read-only access to cache)
    var lessonsByID: [UUID: CDLesson] {
        cacheManager.lessonsByID
    }

    /// Work lookup dictionary (read-only access to cache)
    var workByID: [UUID: CDWorkModel] {
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

    // MARK: - Error Reporting

    /// Throttle: last time a fetch error toast was shown (30s cooldown)
    private var lastErrorToastTime: Date?

    private func showFetchErrorToast(_ collector: FetchErrorCollector) {
        let now = Date()
        if let last = lastErrorToastTime, now.timeIntervalSince(last) < 30 { return }
        lastErrorToastTime = now
        ToastService.shared.showError(collector.summary, actionLabel: "Retry") { [weak self] in
            self?.scheduleReload()
        }
    }

    // MARK: - Scheduling

    // ENERGY OPTIMIZATION: Debounce reloads to prevent excessive database queries
    // during rapid changes (e.g., date picker scrolling, filter changes)
    private var reloadTask: Task<Void, Never>?

    /// Schedules a debounced reload. Use this for data-driven changes that may happen rapidly.
    /// For user-initiated changes, call reload() directly for immediate feedback.
    func scheduleReload() {
        // Cancel any pending reload
        reloadTask?.cancel()

        // Schedule a debounced reload (400ms delay balances responsiveness with energy efficiency)
        reloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(400)) // 400ms debounce
                guard !Task.isCancelled else { return }
                reload()
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    // MARK: - Init

    init(context: NSManagedObjectContext, date: Date = Date(), calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
        AppCalendar.adopt(timeZoneFrom: calendar)
        // Set date without triggering didSet (which would call scheduleReload)
        // The initial reload is deferred to handleViewAppear() via .task to avoid
        // competing with SwiftUI's initial body evaluation for the store coordinator.
        self.date = date.startOfDay

        // Clean up old agenda order entries in the background
        let ctx = context
        Task(priority: .background) { @MainActor in
            TodayAgendaBuilder.cleanupOldOrders(context: ctx)
        }
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

    // swiftlint:disable:next function_body_length
    func reload() {
        let (day, nextDay) = AppCalendar.dayRange(for: date)
        let errorCollector = FetchErrorCollector()

        // PERFORMANCE: Fetch all data first, then batch update @Published properties
        // This reduces view re-renders from 7+ to 1 by coalescing all changes

        // 1. Fetch lessons data
        let lessonsResult = TodayLessonsLoader.fetchLessonsWithIDs(
            day: day, nextDay: nextDay, context: context, errorCollector: errorCollector
        )
        if !lessonsResult.lessons.isEmpty {
            cacheManager.loadStudentsIfNeeded(ids: lessonsResult.neededStudentIDs, context: context)
            cacheManager.loadLessonsIfNeeded(ids: lessonsResult.neededLessonIDs, context: context)
        }
        let filteredLessons = lessonsResult.lessons.isEmpty ? [] :
            TodayLevelFilterService.filterLessons(
                lessonsResult.lessons, studentsByID: studentsByID, levelFilter: levelFilter
            )

        // 2. Fetch work data
        if let prelimResult = TodayDataFetcher.fetchWorkData(
            day: day, nextDay: nextDay, referenceDate: date, context: context,
            errorCollector: errorCollector
        ) {
            cacheManager.loadStudentsIfNeeded(ids: prelimResult.neededStudentIDs, context: context)
            cacheManager.loadLessonsIfNeeded(ids: prelimResult.neededLessonIDs, context: context)
        }
        let workResult = TodayWorkLoader.loadWork(
            day: day, nextDay: nextDay, referenceDate: date,
            studentsByID: studentsByID, levelFilter: levelFilter, context: context,
            errorCollector: errorCollector
        )
        cacheManager.updateWork(workResult.workByID)

        // 3. Fetch completed work
        let completedResult = TodayWorkLoader.fetchCompletedWork(
            day: day, nextDay: nextDay, context: context, errorCollector: errorCollector
        )
        cacheManager.loadStudentsIfNeeded(ids: completedResult.neededStudentIDs, context: context)
        let filteredCompletedWork = TodayLevelFilterService.filterWork(
            completedResult.completedWork, studentsByID: studentsByID, levelFilter: levelFilter
        )

        // 4. Fetch reminders
        let remindersResult = TodayDataFetcher.fetchReminders(
            day: day, nextDay: nextDay, context: context, errorCollector: errorCollector
        )

        // 5. Fetch calendar events
        let calendarEvents = TodayDataFetcher.fetchCalendarEvents(
            day: day, nextDay: nextDay, context: context, errorCollector: errorCollector
        )

        // 6. Fetch scheduled meetings
        let meetingsResult = TodayDataFetcher.fetchScheduledMeetings(day: day, nextDay: nextDay, context: context)
        cacheManager.loadStudentsIfNeeded(ids: meetingsResult.neededStudentIDs, context: context)

        // 6a. Fetch completed meetings
        let completedMeetingsResult = TodayDataFetcher.fetchCompletedMeetings(
            day: day, nextDay: nextDay, context: context
        )
        cacheManager.loadStudentsIfNeeded(ids: completedMeetingsResult.neededStudentIDs, context: context)

        // 7. Fetch attendance
        let attendanceResult = TodayDataFetcher.fetchAttendance(
            day: day, nextDay: nextDay, context: context, errorCollector: errorCollector
        )
        cacheManager.loadStudentsIfNeeded(ids: attendanceResult.neededStudentIDs, context: context)
        let processedAttendance = TodayAttendanceLoader.processAttendance(
            records: attendanceResult.records, studentsByID: studentsByID, levelFilter: levelFilter
        )

        // 7. Fetch recent notes
        let notesResult = TodayDataFetcher.fetchRecentNotes(context: context, errorCollector: errorCollector)
        let missingStudentIDs = notesResult.neededStudentIDs.subtracting(recentNoteStudentsByID.keys)
        var updatedRecentNoteStudents = recentNoteStudentsByID
        
        // PERFORMANCE: Batch fetch all missing students in a single query instead of N queries
        if !missingStudentIDs.isEmpty {
            let studentRequest = CDFetchRequest(CDStudent.self)
            studentRequest.fetchLimit = 500 // Safety limit for student roster
            let allStudents = context.safeFetch(studentRequest).filter(\.isEnrolled)
            let missingStudents = allStudents.filter { student in
                guard let id = student.id else { return false }
                return missingStudentIDs.contains(id)
            }
            for student in missingStudents {
                guard let id = student.id else { continue }
                updatedRecentNoteStudents[id] = student
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
        scheduledMeetings = meetingsResult.meetings
        completedMeetings = completedMeetingsResult.meetings
        attendanceSummary = processedAttendance.summary
        absentToday = processedAttendance.absentStudentIDs
        leftEarlyToday = processedAttendance.leftEarlyStudentIDs
        recentNotes = notesResult.notes
        recentNoteStudentsByID = updatedRecentNoteStudents

        // 8. Build unified agenda
        agendaItems = TodayAgendaBuilder.buildAgenda(
            lessons: filteredLessons,
            meetings: meetingsResult.meetings,
            overdueSchedule: workResult.overdueSchedule,
            todaysSchedule: workResult.todaysSchedule,
            staleFollowUps: workResult.staleFollowUps,
            day: day,
            context: context
        )

        // 9. Surface any fetch errors via toast
        if errorCollector.hasErrors {
            showFetchErrorToast(errorCollector)
        }
    }

    // MARK: - Agenda Reordering

    /// Moves agenda items and persists the new order.
    func moveAgendaItem(from source: IndexSet, to destination: Int) {
        agendaItems.move(fromOffsets: source, toOffset: destination)
        TodayAgendaBuilder.saveOrder(items: agendaItems, day: date, context: context)
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

        // Pre-compute ID comparisons with explicit types to help the type checker
        let lessonsMatch: Bool = lhs.todaysLessons.count == rhs.todaysLessons.count
            && lhs.todaysLessons.map(\.id) == rhs.todaysLessons.map(\.id)
        let workMatch: Bool = lhs.completedWork.count == rhs.completedWork.count
            && lhs.completedWork.map(\.id) == rhs.completedWork.map(\.id)
        let remindersMatch: Bool = lhs.todaysReminders.count == rhs.todaysReminders.count
            && lhs.todaysReminders.map(\.id) == rhs.todaysReminders.map(\.id)
        let calendarMatch: Bool = lhs.todaysCalendarEvents.count == rhs.todaysCalendarEvents.count
            && lhs.todaysCalendarEvents.map(\.id) == rhs.todaysCalendarEvents.map(\.id)
        let meetingsMatch: Bool = lhs.scheduledMeetings.count == rhs.scheduledMeetings.count
            && lhs.scheduledMeetings.map(\.id) == rhs.scheduledMeetings.map(\.id)
            && lhs.completedMeetings.count == rhs.completedMeetings.count
            && lhs.completedMeetings.map(\.id) == rhs.completedMeetings.map(\.id)
        let notesMatch: Bool = lhs.recentNotes.count == rhs.recentNotes.count
            && lhs.recentNotes.map(\.id) == rhs.recentNotes.map(\.id)

        guard lessonsMatch, workMatch, remindersMatch, calendarMatch, meetingsMatch, notesMatch,
              lhs.overdueSchedule.count == rhs.overdueSchedule.count,
              lhs.todaysSchedule.count == rhs.todaysSchedule.count,
              lhs.staleFollowUps.count == rhs.staleFollowUps.count,
              lhs.overdueReminders.count == rhs.overdueReminders.count,
              lhs.anytimeReminders.count == rhs.anytimeReminders.count else {
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
