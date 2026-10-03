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
import OSLog

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

    /// The ready queue, rebuilt only when one of its inputs changes — not on
    /// every attendance tap or todo toggle (see +ReadyForNext).
    let readyQueue: ReadyQueueLoader
    /// Flips when one of `derivedCountInputEntities` changes; made on first use.
    @ObservationIgnored var derivedCountInputs: ManagedObjectChangeFlag?
    /// What `needsLessonCount` was last computed under (see +DerivedCounts).
    @ObservationIgnored var derivedCountsBasis: DerivedCountsBasis?
    /// How many times the count has been computed (for tests pinning the gate).
    @ObservationIgnored var derivedCountsBuildCount = 0
    /// Flips when one of `reloadInputEntities` changes; `reload()` clears it,
    /// so a change Today saved and reloaded for itself asks for nothing more.
    @ObservationIgnored let reloadInputs: ManagedObjectChangeFlag
    /// How many times `reload()` has run (for tests pinning the change gate).
    @ObservationIgnored private(set) var reloadCount = 0

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
    var staleFollowUps: [FollowUpWorkItem] = []
    /// Every stale work item; `staleFollowUps` keeps only the top
    /// `TodayScheduleBuilder.staleRowLimit`.
    var staleTotalCount = 0
    /// Gone quiet's rows: `staleFollowUps`, a group or flexible lesson's
    /// children sharing one row, most quiet first.
    var goneQuietItems: [AgendaItem] = []
    /// Open todos linked to work with a row on Today (Gone quiet, and the
    /// due check-ins in the Todos list), folded onto those rows.
    var linkedTodos: TodayLinkedTodos = .empty

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
    /// Every child marked absent on the selected day, whatever the level
    /// filter (`absentToday` is filtered) — for the lesson rows.
    var absentStudentIDs: Set<UUID> = []
    /// Every child marked present or late on the selected day — who lesson
    /// rows count as here.
    var hereStudentIDs: Set<UUID> = []
    /// Whether any child has an attendance mark today; lesson rows say
    /// "6 of 7 here" only once it is.
    var attendanceTaken = false

    /// Lessons on the day that have a plan to open, decided once per reload.
    var lessonIDsWithPlan: Set<UUID> = []

    // New Outputs for recent notes and their students
    var recentNotes: [CDNote] = []
    var recentNoteStudentsByID: [UUID: CDStudent] = [:]

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
    // during rapid changes (e.g., date picker scrolling, filter changes).
    // The debounce itself lives in TodayViewModel+Refresh.swift.
    @ObservationIgnored var reloadTask: Task<Void, Never>?
    /// A reload asked for outright is pending; a change-gated request that
    /// replaces it must still reload. Cleared by `reload()`.
    @ObservationIgnored var reloadIsRequired = false

    /// Schedules a debounced reload. Use this for data-driven changes that may happen rapidly.
    /// For user-initiated changes, call reload() directly for immediate feedback.
    func scheduleReload() {
        reloadIsRequired = true
        debounceReload()
    }

    // MARK: - Init

    /// How many view models this process has made (for tests pinning that a
    /// redraw of Today's parent makes none; see `TodayRootView`).
    private(set) static var madeCount = 0

    init(context: NSManagedObjectContext, date: Date = Date(), calendar: Calendar = AppCalendar.shared) {
        Self.madeCount += 1
        self.context = context
        self.calendar = calendar
        self.readyQueue = ReadyQueueLoader(context: context)
        // Saves only (see `inputChanges()`): the history processor's signal
        // for Today's own save would land after its reload and ask again.
        self.reloadInputs = ManagedObjectChangeFlag(
            entityNames: Self.reloadInputEntities, context: context, listensForImportSignal: false
        )
        // Set date without triggering didSet (which would call scheduleReload)
        // The initial reload is deferred to handleViewAppear() via .task to avoid
        // competing with SwiftUI's initial body evaluation for the store coordinator.
        self.date = date.startOfDay

        // Clean up old agenda order entries and empty day pads: once a day per
        // store, on a background context. One view model is made per Today
        // screen (`TodayRootView`); until 2026-09-27 `TodayView.init` made one
        // on every redraw of its parent, and this once ran for each of them on
        // the main thread.
        TodayRetentionCleanup.startIfDue(for: context)
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
        let signpost = Self.signposter.beginInterval("Today reload", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("Today reload", signpost) }
        reloadCount += 1
        // Cleared first: a change that lands from here on asks again.
        reloadIsRequired = false
        _ = reloadInputs.consume(pendingIn: context)

        // First, so the ready queue's record read, off the main thread when
        // it can be, runs alongside the fetches below instead of after them.
        refreshReadyForNextIfNeeded()

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

        // 2. Fetch work data once; the schedule and the follow-ups both read it
        let workFetch = TodayDataFetcher.fetchWorkData(
            day: day, nextDay: nextDay, referenceDate: date, context: context,
            errorCollector: errorCollector
        )
        if let workFetch {
            cacheManager.loadStudentsIfNeeded(ids: workFetch.neededStudentIDs, context: context)
            cacheManager.loadLessonsIfNeeded(ids: workFetch.neededLessonIDs, context: context)
        }
        let workResult = TodayWorkLoader.loadWork(
            from: workFetch, referenceDate: date,
            studentsByID: studentsByID, levelFilter: levelFilter, context: context
        )
        cacheManager.updateWork(workResult.workByID)

        // 2b. Due check-ins for the todo list (same fetch, list rules)
        let departed = cacheManager.departedStudents(context: context)
        let followUps = TodayFollowUpLoader.build(
            fetch: workFetch, day: day, nextDay: nextDay,
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

        // 7. Fetch recent notes; their children resolve against the roster snapshot
        let notesResult = TodayDataFetcher.fetchRecentNotes(context: context, errorCollector: errorCollector)
        let missingStudentIDs = notesResult.neededStudentIDs.subtracting(recentNoteStudentsByID.keys)
        let updatedRecentNoteStudents = recentNoteStudentsByID.merging(
            cacheManager.enrolledStudents(ids: missingStudentIDs, context: context)
        ) { _, new in new }

        // 7b. Open todos linked to work on screen, folded onto those rows
        let workIDsOnScreen = Set(workResult.staleFollowUps.compactMap(\.work.id))
            .union(followUps.compactMap(\.work.id))
        let linked = TodayLinkedTodosLoader.load(
            workIDsOnScreen: workIDsOnScreen, day: day, calendar: calendar, context: context
        )

        // BATCH UPDATE: Apply all @Published changes together to minimize view re-renders
        todaysLessons = filteredLessons
        staleFollowUps = workResult.staleFollowUps
        staleTotalCount = workResult.staleTotalCount
        goneQuietItems = TodayAgendaBuilder.groupFollowUpWork(workResult.staleFollowUps)
        linkedTodos = linked
        completedWork = filteredCompletedWork
        overdueReminders = remindersResult.overdue
        todaysReminders = remindersResult.today
        anytimeReminders = remindersResult.anytime
        todaysCalendarEvents = calendarEvents
        scheduledMeetings = TodayAgendaBuilder.orderMeetings(meetingsResult.meetings, day: day, context: context)
        completedMeetings = completedMeetingsResult.meetings
        attendanceSummary = processedAttendance.summary
        absentToday = processedAttendance.absentStudentIDs
        leftEarlyToday = processedAttendance.leftEarlyStudentIDs
        absentStudentIDs = TodayAttendanceLoader.absentStudentIDs(in: attendanceResult.records)
        hereStudentIDs = TodayAttendanceLoader.hereStudentIDs(in: attendanceResult.records)
        attendanceTaken = TodayAttendanceLoader.isTaken(in: attendanceResult.records)
        lessonIDsWithPlan = TodayLessonsLoader.lessonIDsWithPlan(for: filteredLessons, lessonsByID: lessonsByID)
        recentNotes = notesResult.notes
        recentNoteStudentsByID = updatedRecentNoteStudents
        followUpCheckIns = followUps
        departedStudentsByID = departed

        // 8. Build unified agenda. Due check-ins live in the todo list now
        // (followUpCheckIns), and quiet work in Gone quiet (goneQuietItems),
        // so the agenda is built without them.
        agendaItems = TodayAgendaBuilder.buildAgenda(
            lessons: filteredLessons,
            overdueSchedule: [],
            todaysSchedule: [],
            day: day,
            context: context
        )

        // 9. Surface any fetch errors via toast
        if errorCollector.hasErrors {
            showFetchErrorToast(errorCollector)
        }
    }
}
