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
import Combine

/// View model for the Today screen.
/// - Manages date selection and a level filter.
/// - Builds in-memory caches to avoid repeated fetches per row.
@MainActor
final class TodayViewModel: ObservableObject {

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

    @Published var date: Date {
        didSet {
            let normalized = date.startOfDay
            if date != normalized {
                date = normalized
                return
            }
            scheduleReload()
        }
    }
    @Published var levelFilter: LevelFilter = .all { didSet { scheduleReload() } }

    // MARK: - Outputs

    @Published var todaysLessons: [StudentLesson] = []

    // WorkModel-based lists
    @Published var overdueSchedule: [ScheduledWorkItem] = []
    @Published var todaysSchedule: [ScheduledWorkItem] = []
    @Published var staleFollowUps: [FollowUpWorkItem] = []

    // Completed work items
    @Published var completedWork: [WorkModel] = []

    // Reminders for today
    @Published var todaysReminders: [Reminder] = []
    @Published var overdueReminders: [Reminder] = []
    @Published var anytimeReminders: [Reminder] = []  // Reminders with no due date

    // Calendar events for today
    @Published var todaysCalendarEvents: [CalendarEvent] = []

    @Published var attendanceSummary: AttendanceSummary = AttendanceSummary()
    @Published var absentToday: [UUID] = []
    @Published var leftEarlyToday: [UUID] = []

    // New Published Outputs for recent notes and their students
    @Published var recentNotes: [Note] = []
    @Published var recentNoteStudentsByID: [UUID: Student] = [:]

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
    private var reloadTask: Task<Void, Never>?

    /// Schedules a debounced reload. Use this for data-driven changes that may happen rapidly.
    /// For user-initiated changes, call reload() directly for immediate feedback.
    func scheduleReload() {
        // Cancel any pending reload
        reloadTask?.cancel()

        // Schedule a debounced reload (400ms delay balances responsiveness with energy efficiency)
        reloadTask = Task { @MainActor in
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

    deinit {
        // Cancel any pending reload task to prevent leaks and unnecessary work
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

        // Load lessons and their related data
        reloadLessons(day: day, nextDay: nextDay)

        // Load work items and schedule
        reloadWork(day: day, nextDay: nextDay)

        // Load completed work
        reloadCompletedWork(day: day, nextDay: nextDay)

        // Load reminders
        reloadReminders(day: day, nextDay: nextDay)

        // Load calendar events
        reloadCalendarEvents(day: day, nextDay: nextDay)

        // Load attendance
        reloadAttendance(day: day, nextDay: nextDay)

        // Load recent notes and their students
        reloadRecentNotes()
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

    // MARK: - Private Reload Methods (delegated to TodayDataFetcher and TodayScheduleBuilder)

    /// Fetches and loads lessons for today, along with their related students and lessons
    private func reloadLessons(day: Date, nextDay: Date) {
        let result = TodayLessonsLoader.fetchLessonsWithIDs(day: day, nextDay: nextDay, context: context)

        if result.lessons.isEmpty {
            todaysLessons = []
            return
        }

        // Load only needed students and lessons using cache manager
        cacheManager.loadStudentsIfNeeded(ids: result.neededStudentIDs, context: context)
        cacheManager.loadLessonsIfNeeded(ids: result.neededLessonIDs, context: context)

        // Filter today's lessons by level
        todaysLessons = TodayLevelFilterService.filterLessons(result.lessons, studentsByID: studentsByID, levelFilter: levelFilter)
    }

    /// Loads work models, plan items, and processes schedule logic
    private func reloadWork(day: Date, nextDay: Date) {
        // Load work-related students first (needed for level filtering in schedule builder)
        // We do a preliminary fetch to get needed IDs before building the schedule
        if let prelimResult = TodayDataFetcher.fetchWorkData(day: day, nextDay: nextDay, referenceDate: date, context: context) {
            cacheManager.loadStudentsIfNeeded(ids: prelimResult.neededStudentIDs, context: context)
            cacheManager.loadLessonsIfNeeded(ids: prelimResult.neededLessonIDs, context: context)
        }

        let result = TodayWorkLoader.loadWork(
            day: day,
            nextDay: nextDay,
            referenceDate: date,
            studentsByID: studentsByID,
            levelFilter: levelFilter,
            context: context
        )

        // Update work cache
        cacheManager.updateWork(result.workByID)

        self.overdueSchedule = result.overdueSchedule
        self.todaysSchedule = result.todaysSchedule
        self.staleFollowUps = result.staleFollowUps
    }

    /// Loads completed work items for today
    private func reloadCompletedWork(day: Date, nextDay: Date) {
        let result = TodayWorkLoader.fetchCompletedWork(day: day, nextDay: nextDay, context: context)

        // Load students for completed work that aren't already cached
        cacheManager.loadStudentsIfNeeded(ids: result.neededStudentIDs, context: context)

        completedWork = TodayLevelFilterService.filterWork(result.completedWork, studentsByID: studentsByID, levelFilter: levelFilter)
    }

    private func reloadReminders(day: Date, nextDay: Date) {
        let result = TodayDataFetcher.fetchReminders(day: day, nextDay: nextDay, context: context)
        self.overdueReminders = result.overdue
        self.todaysReminders = result.today
        self.anytimeReminders = result.anytime
    }

    private func reloadCalendarEvents(day: Date, nextDay: Date) {
        self.todaysCalendarEvents = TodayDataFetcher.fetchCalendarEvents(
            day: day,
            nextDay: nextDay,
            context: context
        )
    }

    private func reloadAttendance(day: Date, nextDay: Date) {
        let result = TodayDataFetcher.fetchAttendance(day: day, nextDay: nextDay, context: context)

        // Load students referenced in attendance records if not already loaded
        cacheManager.loadStudentsIfNeeded(ids: result.neededStudentIDs, context: context)

        // Process attendance using TodayAttendanceLoader
        let attendanceResult = TodayAttendanceLoader.processAttendance(
            records: result.records,
            studentsByID: studentsByID,
            levelFilter: levelFilter
        )

        self.attendanceSummary = attendanceResult.summary
        self.absentToday = attendanceResult.absentStudentIDs
        self.leftEarlyToday = attendanceResult.leftEarlyStudentIDs
    }

    /// Loads recent notes from the last 7 days and their associated students
    private func reloadRecentNotes() {
        let result = TodayDataFetcher.fetchRecentNotes(context: context)
        self.recentNotes = result.notes

        // Determine missing student IDs that are not in recentNoteStudentsByID
        let missingIDs = result.neededStudentIDs.subtracting(recentNoteStudentsByID.keys)
        guard !missingIDs.isEmpty else { return }

        // Fetch missing students
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let allStudents = context.safeFetch(FetchDescriptor<Student>())
        let filtered = allStudents.filter { missingIDs.contains($0.id) }
        for student in filtered {
            recentNoteStudentsByID[student.id] = student
        }
    }

}
