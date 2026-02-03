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
            // Clear recent notes student cache when date changes to prevent unbounded growth
            recentNoteStudentsByID.removeAll(keepingCapacity: true)
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
        for studentID in missingStudentIDs {
            var descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
            descriptor.fetchLimit = 1
            if let student = context.safeFetch(descriptor).first {
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
