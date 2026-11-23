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
    @ObservationIgnored private var calendar: Calendar
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
    // `private(set)` where only this file writes; `agendaItems`, `scheduledMeetings`
    // and `needsLessonCount` are written by extensions in other files.

    private(set) var todaysLessons: [CDLessonAssignment] = []

    // CDWorkModel-based lists
    private(set) var staleFollowUps: [FollowUpWorkItem] = []
    /// Every stale work item; `staleFollowUps` keeps only the top
    /// `TodayScheduleBuilder.staleRowLimit`.
    private(set) var staleTotalCount = 0
    /// Gone quiet's rows: `staleFollowUps`, a group or flexible lesson's
    /// children sharing one row, most quiet first.
    private(set) var goneQuietItems: [AgendaItem] = []
    /// Open todos linked to work with a row on Today (Gone quiet, and the
    /// due check-ins in the Todos list), folded onto those rows.
    private(set) var linkedTodos: TodayLinkedTodos = .empty

    // Unified agenda (lessons + work items, user-orderable)
    var agendaItems: [AgendaItem] = []

    // Completed work items
    private(set) var completedWork: [CDWorkModel] = []

    // Calendar events for today
    private(set) var todaysCalendarEvents: [CDCalendarEvent] = []

    // Scheduled meetings for today
    var scheduledMeetings: [CDScheduledMeeting] = []

    // Completed meetings for today
    private(set) var completedMeetings: [CDStudentMeeting] = []

    /// The day's blocks on the Schedules timetable, in time order (`TodayScheduleRows`).
    private(set) var scheduleRows: [TodayScheduleRows.Row] = []

    private(set) var attendanceSummary: AttendanceSummary = AttendanceSummary()
    private(set) var absentToday: [UUID] = []
    private(set) var leftEarlyToday: [UUID] = []
    /// Every child marked absent on the selected day, whatever the level
    /// filter (`absentToday` is filtered) — for the lesson rows.
    private(set) var absentStudentIDs: Set<UUID> = []
    /// Every child marked present or late on the selected day — who lesson
    /// rows count as here.
    private(set) var hereStudentIDs: Set<UUID> = []
    /// Whether any child has an attendance mark today; lesson rows say
    /// "6 of 7 here" only once it is.
    private(set) var attendanceTaken = false

    /// Lessons on the day that have a plan to open, decided once per reload.
    private(set) var lessonIDsWithPlan: Set<UUID> = []

    /// "Still practicing: …" for each lesson not yet given, by presentation
    /// id, decided once per reload (`TodayViewModel+StillPracticing.swift`).
    private(set) var stillPracticingLines: [UUID: String] = [:]

    // New Outputs for recent notes and their students
    private(set) var recentNotes: [CDNote] = []
    private(set) var recentNoteStudentsByID: [UUID: CDStudent] = [:]

    /// Enrolled children overdue for a lesson, for the "Needs Lesson" day card.
    var needsLessonCount = 0

    /// What Restock needs, for the Restock day card (shown only when
    /// something is needed). Read in every reload: a few open needs.
    private(set) var restockDigest = RestockDigest.empty

    /// Due and overdue work check-ins, one per work, for the todo list.
    /// Departed children's rows are kept and marked (see TodayFollowUpLoader).
    private(set) var followUpCheckIns: [WorkCheckInFollowUp] = []
    /// Former students named on those rows — the enrolled cache never holds them.
    private(set) var departedStudentsByID: [UUID: CDStudent] = [:]
    /// Every child the day's meetings name who is still in the notebook,
    /// enrolled or not, for the meeting rows' names.
    private(set) var meetingStudentsByID: [UUID: CDStudent] = [:]

    // MARK: - Cache Accessors (delegate to cacheManager)

    /// Students lookup dictionary (read-only access to cache)
    var studentsByID: [UUID: CDStudent] { cacheManager.studentsByID }

    /// Lessons lookup dictionary (read-only access to cache)
    var lessonsByID: [UUID: CDLesson] { cacheManager.lessonsByID }

    /// Returns the display name for a student ID
    func displayName(for studentID: UUID) -> String { cacheManager.displayName(for: studentID) }

    /// Returns the lesson name for a lesson ID
    func lessonName(for lessonID: UUID) -> String { cacheManager.lessonName(for: lessonID) }

    // MARK: - Error Reporting

    /// Throttle: last time a fetch error toast was shown (30s cooldown)
    @ObservationIgnored private var lastErrorToastTime: Date?

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
        // store, on a background context (`TodayRetentionCleanup` has the history).
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

        // PERFORMANCE: Fetch all data first, then batch update the observed properties
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
            studentsByID: studentsByID, departedStudentsByID: departed, levelFilter: levelFilter,
            context: context
        )

        // 3. Fetch completed work
        let completedResult = TodayWorkLoader.fetchCompletedWork(
            day: day, nextDay: nextDay, context: context, errorCollector: errorCollector
        )
        cacheManager.loadStudentsIfNeeded(ids: completedResult.neededStudentIDs, context: context)
        let filteredCompletedWork = TodayLevelFilterService.filterWork(
            completedResult.completedWork, studentsByID: studentsByID, levelFilter: levelFilter
        )

        // 5. Fetch calendar events
        let calendarEvents = TodayDataFetcher.fetchCalendarEvents(
            day: day, nextDay: nextDay, context: context, errorCollector: errorCollector
        )

        // 6. Fetch scheduled meetings, and the day on the Schedules timetable
        let meetingsResult = TodayDataFetcher.fetchScheduledMeetings(day: day, nextDay: nextDay, context: context)
        let scheduleDay = TodayScheduleRows.day(day, in: context, calendar: calendar)
        cacheManager.loadStudentsIfNeeded(ids: meetingsResult.neededStudentIDs, context: context)

        // 6a. Fetch completed meetings
        let completedMeetingsResult = TodayDataFetcher.fetchCompletedMeetings(
            day: day, nextDay: nextDay, context: context
        )
        cacheManager.loadStudentsIfNeeded(ids: completedMeetingsResult.neededStudentIDs, context: context)
        let meetingStudentIDs = meetingsResult.neededStudentIDs.union(completedMeetingsResult.neededStudentIDs)
        // Hidden test students' meetings and notes stay off Today (#55).
        let hiddenIDs = cacheManager.hiddenStudentIDs(context: context)
        let meetingDeparted = departed.filter { meetingStudentIDs.contains($0.key) && !hiddenIDs.contains($0.key) }
        let meetingStudents = cacheManager.enrolledStudents(ids: meetingStudentIDs, context: context)
            .merging(meetingDeparted) { enrolled, _ in enrolled }

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
        let updatedRecentNoteStudents = recentNoteStudentsByID.filter { !hiddenIDs.contains($0.key) }.merging(
            cacheManager.enrolledStudents(ids: missingStudentIDs, context: context)
        ) { _, new in new }

        // 7b. Open todos linked to work on screen, folded onto those rows
        let workIDsOnScreen = Set(workResult.staleFollowUps.compactMap(\.work.id))
            .union(followUps.compactMap(\.work.id))
        let linked = TodayLinkedTodosLoader.load(
            workIDsOnScreen: workIDsOnScreen, day: day, calendar: calendar, context: context
        )

        // 7c. Restock's open needs, for its day card
        let restock = TodayRestockLoader.digest(in: context)

        // BATCH UPDATE: Apply all observed changes together to minimize view re-renders
        todaysLessons = filteredLessons
        staleFollowUps = workResult.staleFollowUps
        staleTotalCount = workResult.staleTotalCount
        goneQuietItems = TodayAgendaBuilder.groupFollowUpWork(workResult.staleFollowUps)
        linkedTodos = linked
        completedWork = filteredCompletedWork
        todaysCalendarEvents = calendarEvents
        scheduledMeetings = TodayAgendaBuilder.orderMeetings(
            TodayMeetingRows.filter(
                TodayHiddenStudents.meetings(meetingsResult.meetings, hiding: hiddenIDs),
                studentsByID: studentsByID, levelFilter: levelFilter
            ),
            day: day, context: context
        )
        completedMeetings = TodayMeetingRows.filterCompleted(
            TodayHiddenStudents.completedMeetings(completedMeetingsResult.meetings, hiding: hiddenIDs),
            studentsByID: studentsByID, levelFilter: levelFilter
        )
        meetingStudentsByID = meetingStudents
        scheduleRows = TodayScheduleRows.rows(scheduleDay, students: studentsByID)
        attendanceSummary = processedAttendance.summary
        absentToday = processedAttendance.absentStudentIDs
        leftEarlyToday = processedAttendance.leftEarlyStudentIDs
        absentStudentIDs = TodayAttendanceLoader.absentStudentIDs(in: attendanceResult.records)
        hereStudentIDs = TodayAttendanceLoader.hereStudentIDs(in: attendanceResult.records)
        attendanceTaken = TodayAttendanceLoader.isTaken(in: attendanceResult.records)
        lessonIDsWithPlan = TodayLessonsLoader.lessonIDsWithPlan(for: filteredLessons, lessonsByID: lessonsByID)
        let practicing = Self.stillPracticingLines(
            for: filteredLessons, lessons: lessonCatalog?.all, names: { [studentsByID] in studentsByID[$0]?.shortName },
            in: context
        )
        if practicing != stillPracticingLines { stillPracticingLines = practicing }
        recentNotes = TodayHiddenStudents.notes(notesResult.notes, hiding: hiddenIDs)
        recentNoteStudentsByID = updatedRecentNoteStudents
        followUpCheckIns = followUps
        departedStudentsByID = departed
        if restock != restockDigest { restockDigest = restock }

        // 8. Build unified agenda. Due check-ins live in the todo list now
        // (followUpCheckIns), and quiet work in Gone quiet (goneQuietItems),
        // so the agenda is built without them.
        agendaItems = TodayAgendaBuilder.buildAgenda(
            lessons: filteredLessons,
            day: day,
            context: context
        )

        // 9. Surface any fetch errors via toast
        if errorCollector.hasErrors {
            showFetchErrorToast(errorCollector)
        }

        // 10. The needs-a-lesson card. A reload follows edits made elsewhere
        // (a lesson given in another window, synced, or over MCP) while Today
        // stays open, as the Mac's does all day; only an appearance or a date
        // change recounted it before (bug hunt 2026-10-17, #41). Its change
        // flag skips the count when nothing it reads moved.
        reloadDerivedCountsIfNeeded(calendar: calendar)
    }
}
