// TodayViewModel.swift
// View model powering the Today hub. Fetches lessons, work items, and plan items
// for the selected day. Uses lightweight lookup caches to avoid per-row fetches.
//
// Delegates to:
// - TodayDataFetcher: All database fetch operations
// - TodayScheduleBuilder: Schedule construction from work data
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
final class TodayViewModel {

    // MARK: - Type Aliases (for backwards compatibility)

    typealias AttendanceSummary = CosmicDaybook.AttendanceSummary
    typealias LevelFilter = CosmicDaybook.LevelFilter

    // MARK: - Dependencies

    let context: NSManagedObjectContext
    private var calendar: Calendar
    private let cacheManager = TodayCacheManager()

    /// Flips when one of `readyForNextInputEntities` changes, so `reload()`
    /// rebuilds the queue only then — not on every attendance tap or todo toggle.
    @ObservationIgnored let readyForNextInputs: ManagedObjectChangeFlag
    /// The test-student preference the queue was last built under; it filters
    /// the roster without touching the store.
    @ObservationIgnored var readyForNextHiddenNames: Set<String>?
    /// How many times the queue has been built (for tests pinning the gate).
    @ObservationIgnored var readyForNextBuildCount = 0
    /// The live lesson catalog bound to `context`, when the view supplies one.
    @ObservationIgnored weak var lessonCatalog: LessonCatalog?
    /// Flips when one of `derivedCountInputEntities` changes; made on first use.
    @ObservationIgnored var derivedCountInputs: ManagedObjectChangeFlag?
    /// What `needsLessonCount` was last computed under (see +DerivedCounts).
    @ObservationIgnored var derivedCountsBasis: DerivedCountsBasis?
    /// How many times the count has been computed (for tests pinning the gate).
    @ObservationIgnored var derivedCountsBuildCount = 0

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

    /// Who the record says is waiting on a next lesson — the capture-time
    /// confirmations and mastery marks, turned into the lessons they point at.
    var readyForNext: [ReadyForNextItem] = []

    /// Enrolled children overdue for a lesson, for the "Needs Lesson" day card.
    var needsLessonCount = 0

    /// Due and overdue work check-ins, one per work, for the todo list.
    /// Departed children's rows are kept and marked (see TodayFollowUpLoader).
    var followUpCheckIns: [WorkCheckInFollowUp] = []
    /// Former students named on those rows — the enrolled cache never holds them.
    var departedStudentsByID: [UUID: CDStudent] = [:]

    // MARK: - Cache Accessors (delegate to cacheManager)

    /// Students lookup dictionary (read-only access to cache)
    var studentsByID: [UUID: CDStudent] {
        cacheManager.studentsByID
    }

    /// Lessons lookup dictionary (read-only access to cache)
    var lessonsByID: [UUID: CDLesson] {
        cacheManager.lessonsByID
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
        reloadTask = Task { [weak self] in
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

    init(context: NSManagedObjectContext, date: Date = Date(), calendar: Calendar = AppCalendar.shared) {
        self.context = context
        self.calendar = calendar
        self.readyForNextInputs = ManagedObjectChangeFlag(
            entityNames: Self.readyForNextInputEntities, context: context
        )
        // Set date without triggering didSet (which would call scheduleReload)
        // The initial reload is deferred to handleViewAppear() via .task to avoid
        // competing with SwiftUI's initial body evaluation for the store coordinator.
        self.date = date.startOfDay

        // Clean up old agenda order entries and empty day pads in the background
        let ctx = context
        Task(priority: .background) { @MainActor in
            TodayAgendaBuilder.cleanupOldOrders(context: ctx)
            TodayAgendaBuilder.cleanupOldDayPads(context: ctx)
        }
    }

    func setCalendar(_ cal: Calendar) {
        self.calendar = cal
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
        let prelimResult = TodayDataFetcher.fetchWorkData(
            day: day, nextDay: nextDay, referenceDate: date, context: context,
            errorCollector: errorCollector
        )
        if let prelimResult {
            cacheManager.loadStudentsIfNeeded(ids: prelimResult.neededStudentIDs, context: context)
            cacheManager.loadLessonsIfNeeded(ids: prelimResult.neededLessonIDs, context: context)
        }
        let workResult = TodayWorkLoader.loadWork(
            day: day, nextDay: nextDay, referenceDate: date,
            studentsByID: studentsByID, levelFilter: levelFilter, context: context,
            errorCollector: errorCollector
        )
        cacheManager.updateWork(workResult.workByID)

        // 2b. Due check-ins for the todo list (same fetch, list rules)
        let departed = TodayFollowUpLoader.fetchDepartedStudents(context: context)
        let followUps = TodayFollowUpLoader.build(
            fetch: prelimResult, day: day, nextDay: nextDay,
            studentsByID: studentsByID, departedStudentsByID: departed, levelFilter: levelFilter
        )

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
            let allStudents = context.safeFetch(studentRequest).filterEnrolled()
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
        refreshReadyForNextIfNeeded()
        followUpCheckIns = followUps
        departedStudentsByID = departed

        // 8. Build unified agenda. Due check-ins live in the todo list now
        // (followUpCheckIns), so the agenda is built without them; the
        // overdueSchedule/todaysSchedule outputs stay for Right Now's count.
        agendaItems = TodayAgendaBuilder.buildAgenda(
            lessons: filteredLessons,
            meetings: meetingsResult.meetings,
            overdueSchedule: [],
            todaysSchedule: [],
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

}
