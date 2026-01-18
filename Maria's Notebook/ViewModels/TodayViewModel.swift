// TodayViewModel.swift
// View model powering the Today hub. Fetches lessons, work contracts, and plan items
// for the selected day. Uses lightweight lookup caches to avoid per-row fetches.
//
// Delegates to:
// - TodayDataFetcher: All database fetch operations
// - TodayScheduleBuilder: Schedule construction from work data
// - TodayCacheManager: Student/lesson/work caching (used internally)

import Foundation
import SwiftUI
import SwiftData
import Combine

/// Data structure for a scheduled check-in (explicit WorkPlanItem).
struct ContractScheduleItem: Identifiable {
    let work: WorkModel
    let planItem: WorkPlanItem
    var id: UUID { planItem.id }
}

/// Data structure for a stale follow-up (implicit WorkModel aging).
struct ContractFollowUpItem: Identifiable {
    let work: WorkModel
    let daysSinceTouch: Int
    var id: UUID { work.id }
}

/// View model for the Today screen.
/// - Manages date selection and a level filter.
/// - Builds in-memory caches to avoid repeated fetches per row.
@MainActor
final class TodayViewModel: ObservableObject {
    // MARK: - Types
    /// Lightweight counts shown in the Today header.
    struct AttendanceSummary {
        var presentCount: Int = 0
        var tardyCount: Int = 0
        var absentCount: Int = 0
        var leftEarlyCount: Int = 0
    }

    /// Filter for Lower/Upper/All levels. Used to reduce the visible items across sections.
    enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
        var id: String { rawValue }
        func matches(_ level: Student.Level) -> Bool {
            switch self {
            case .all: return true
            case .lower: return level == .lower
            case .upper: return level == .upper
            }
        }
    }

    // MARK: - Dependencies
    private let context: ModelContext
    private var calendar: Calendar

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
    @Published var overdueSchedule: [ContractScheduleItem] = []
    @Published var todaysSchedule: [ContractScheduleItem] = []
    @Published var staleFollowUps: [ContractFollowUpItem] = []

    // Completed work items
    @Published var completedContracts: [WorkModel] = []

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

    // MARK: - Caches
    @Published private(set) var studentsByID: [UUID: Student] = [:] {
        didSet {
            // Invalidate duplicate names cache when students change
            _cachedDuplicateFirstNames = nil
        }
    }
    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    // Caching work by ID for generic lookups if needed
    @Published private(set) var workByID: [UUID: WorkModel] = [:]

    // PERFORMANCE OPTIMIZATION: Cache duplicate first names to avoid recalculating on every access
    private var _cachedDuplicateFirstNames: Set<String>?
    var duplicateFirstNames: Set<String> {
        if let cached = _cachedDuplicateFirstNames {
            return cached
        }
        let firsts = studentsByID.values.map { $0.firstName.trimmed().lowercased() }
        var counts: [String: Int] = [:]
        for f in firsts { counts[f, default: 0] += 1 }
        let duplicates = Set(counts.filter { $0.value > 1 }.map { $0.key })
        _cachedDuplicateFirstNames = duplicates
        return duplicates
    }

    // PERFORMANCE OPTIMIZATION: Helper to get display name for a student ID
    // This avoids recreating closures in the view
    func displayName(for studentID: UUID) -> String {
        guard let student = studentsByID[studentID] else { return "Student" }
        let first = student.firstName
        let key = first.trimmed().lowercased()
        if duplicateFirstNames.contains(key) {
            if let initialChar = student.lastName.trimmed().first {
                return "\(first) \(String(initialChar).uppercased())."
            }
        }
        return first
    }

    // PERFORMANCE OPTIMIZATION: Helper to get lesson name
    func lessonName(for lessonID: UUID) -> String {
        lessonsByID[lessonID]?.name ?? "Lesson"
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

        // Load work contracts and schedule
        reloadContracts(day: day, nextDay: nextDay)

        // Load completed contracts
        reloadCompletedContracts(day: day, nextDay: nextDay)

        // Load reminders
        reloadReminders(day: day, nextDay: nextDay)

        // Load calendar events
        reloadCalendarEvents(day: day, nextDay: nextDay)

        // Load attendance
        reloadAttendance(day: day, nextDay: nextDay)

        // Load recent notes and their students
        reloadRecentNotes()
    }

    // MARK: - Private Reload Methods (delegated to TodayDataFetcher and TodayScheduleBuilder)

    /// Fetches and loads lessons for today, along with their related students and lessons
    private func reloadLessons(day: Date, nextDay: Date) {
        let dayLessons = TodayDataFetcher.fetchLessons(day: day, nextDay: nextDay, context: context)

        if dayLessons.isEmpty {
            todaysLessons = []
            return
        }

        // Collect IDs from today's lessons
        var neededStudentIDs = Set<UUID>()
        var neededLessonIDs = Set<UUID>()

        for sl in dayLessons {
            neededStudentIDs.formUnion(sl.resolvedStudentIDs)
            neededLessonIDs.insert(sl.resolvedLessonID)
        }

        // Load only needed students and lessons
        loadStudentsIfNeeded(ids: neededStudentIDs)
        loadLessonsIfNeeded(ids: neededLessonIDs)

        // Filter today's lessons by level
        todaysLessons = filterByLevelIfNeeded(dayLessons, studentsByID: studentsByID)
    }

    /// Loads students if not already cached
    private func loadStudentsIfNeeded(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let missingIDs = ids.filter { studentsByID[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        do {
            let studentsDescriptor = FetchDescriptor<Student>(
                predicate: #Predicate { missingIDs.contains($0.id) }
            )
            let fetchedStudents = try context.fetch(studentsDescriptor)
            let visibleStudents = TestStudentsFilter.filterVisible(fetchedStudents)
            for student in visibleStudents {
                studentsByID[student.id] = student
            }
        } catch {
            let allStudents = context.safeFetch(FetchDescriptor<Student>())
            let visibleStudents = TestStudentsFilter.filterVisible(allStudents)
            for student in visibleStudents where ids.contains(student.id) {
                studentsByID[student.id] = student
            }
        }
    }

    /// Loads lessons if not already cached
    private func loadLessonsIfNeeded(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let missingIDs = ids.filter { lessonsByID[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        do {
            let lessonsDescriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate { missingIDs.contains($0.id) }
            )
            let fetchedLessons = try context.fetch(lessonsDescriptor)
            for lesson in fetchedLessons {
                lessonsByID[lesson.id] = lesson
            }
        } catch {
            let lessons = context.safeFetch(FetchDescriptor<Lesson>())
            for lesson in lessons where ids.contains(lesson.id) {
                lessonsByID[lesson.id] = lesson
            }
        }
    }

    /// Loads work models, plan items, and processes schedule logic
    private func reloadContracts(day: Date, nextDay: Date) {
        guard let result = TodayDataFetcher.fetchWorkData(
            day: day,
            nextDay: nextDay,
            referenceDate: date,
            context: context
        ) else {
            self.overdueSchedule = []
            self.todaysSchedule = []
            self.staleFollowUps = []
            return
        }

        // Update work cache
        workByID = Dictionary(uniqueKeysWithValues: result.workItems.map { ($0.id, $0) })

        // Load work-related students and lessons if not already loaded
        loadStudentsIfNeeded(ids: result.neededStudentIDs)
        loadLessonsIfNeeded(ids: result.neededLessonIDs)

        // Build schedule using TodayScheduleBuilder
        let schedule = TodayScheduleBuilder.buildSchedule(
            workItems: result.workItems,
            planItemsByWork: result.planItemsByWork,
            notesByWork: result.notesByWork,
            studentsByID: studentsByID,
            levelFilter: levelFilter,
            referenceDate: date,
            modelContext: context
        )

        self.overdueSchedule = schedule.overdue
        self.todaysSchedule = schedule.today
        self.staleFollowUps = schedule.stale
    }

    /// Loads completed work items for today
    private func reloadCompletedContracts(day: Date, nextDay: Date) {
        let workItems = TodayDataFetcher.fetchCompletedWork(day: day, nextDay: nextDay, context: context)

        // Load students for completed work that aren't already cached
        var completedWorkStudentIDs = Set<UUID>()
        for work in workItems {
            if let sid = UUID(uuidString: work.studentID) {
                completedWorkStudentIDs.insert(sid)
            }
        }
        loadStudentsIfNeeded(ids: completedWorkStudentIDs)

        completedContracts = workItems.filter { w in
            guard let uuid = UUID(uuidString: w.studentID),
                  let s = self.studentsByID[uuid] else { return false }
            return levelFilter.matches(s.level)
        }
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
        for sid in result.neededStudentIDs where studentsByID[sid] == nil {
            if let student = context.safeFetchFirst(FetchDescriptor<Student>(
                predicate: #Predicate { $0.id == sid }
            )) {
                let visible = TestStudentsFilter.filterVisible([student])
                if let s = visible.first {
                    studentsByID[sid] = s
                }
            }
        }
        self.studentsByID = studentsByID

        var present = 0
        var tardy = 0
        var absent = 0
        var leftEarly = 0
        var absentIDs: Set<UUID> = []
        var leftEarlyIDs: Set<UUID> = []

        for rec in result.records {
            guard let studentIDUUID = rec.studentID.asUUID,
                  let s = self.studentsByID[studentIDUUID] else { continue }
            if !levelFilter.matches(s.level) { continue }
            switch rec.status {
            case .present:
                present += 1
            case .tardy:
                tardy += 1
            case .absent:
                absent += 1
                absentIDs.insert(studentIDUUID)
            case .leftEarly:
                leftEarly += 1
                leftEarlyIDs.insert(studentIDUUID)
            case .unmarked: break
            }
        }

        attendanceSummary = AttendanceSummary(
            presentCount: present + tardy,
            tardyCount: tardy,
            absentCount: absent,
            leftEarlyCount: leftEarly
        )
        self.absentToday = Array(absentIDs)
        self.leftEarlyToday = Array(leftEarlyIDs)
    }

    /// Loads recent notes from the last 7 days and their associated students
    private func reloadRecentNotes() {
        let result = TodayDataFetcher.fetchRecentNotes(context: context)
        self.recentNotes = result.notes

        // Determine missing student IDs that are not in recentNoteStudentsByID
        let missingIDs = result.neededStudentIDs.subtracting(recentNoteStudentsByID.keys)
        guard !missingIDs.isEmpty else { return }

        // Fetch missing students
        do {
            let studentsDescriptor = FetchDescriptor<Student>(
                predicate: #Predicate { missingIDs.contains($0.id) }
            )
            let fetchedStudents = try context.fetch(studentsDescriptor)
            for student in fetchedStudents {
                recentNoteStudentsByID[student.id] = student
            }
        } catch {
            // Silently fail - students will show as "Student"
        }
    }

    // MARK: - Helpers
    private func filterByLevelIfNeeded(_ lessons: [StudentLesson], studentsByID: [UUID: Student]) -> [StudentLesson] {
        guard levelFilter != .all else {
            return lessons.filter { sl in
                let ids = sl.resolvedStudentIDs
                if ids.isEmpty { return true }
                return ids.contains { studentsByID[$0] != nil }
            }
        }
        return lessons.filter { sl in
            let ids = sl.resolvedStudentIDs
            if ids.isEmpty { return true }
            var anyVisible = false
            var anyVisibleMatching = false
            for sid in ids {
                if let s = studentsByID[sid] {
                    anyVisible = true
                    if levelFilter.matches(s.level) { anyVisibleMatching = true }
                }
            }
            return anyVisible && anyVisibleMatching
        }
    }
    
    /// Synchronous helper that determines if a date is a non-school day using cached data.
    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: context)
        return schoolDayCache.isNonSchoolDay(date)
    }

    /// Synchronous helper that returns the next school day strictly after the given date.
    private func nextSchoolDaySync(after date: Date) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: context)

        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the following day
        d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        // Safety cap to avoid infinite loops in case of data errors
        for _ in 0..<730 { // up to ~2 years
            if !schoolDayCache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    /// Synchronous helper that returns the previous school day strictly before the given date.
    private func previousSchoolDaySync(before date: Date) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: context)

        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the previous day
        d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        for _ in 0..<730 { // up to ~2 years
            if !schoolDayCache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }
    
    /// Finds the next day (after the given date) that has lessons scheduled.
    /// Only considers school days and respects the current level filter.
    func nextDayWithLessons(after date: Date) -> Date {
        var current = nextSchoolDaySync(after: date)
        // Safety cap: search up to 2 years forward
        for _ in 0..<730 {
            let (day, nextDay) = AppCalendar.dayRange(for: current)
            do {
                let descriptor = FetchDescriptor<StudentLesson>(
                    predicate: #Predicate { sl in
                        sl.scheduledForDay >= day && sl.scheduledForDay < nextDay
                    }
                )
                let lessons = try context.fetch(descriptor)
                if !lessons.isEmpty {
                    // Check if any lessons match the level filter
                    var neededStudentIDs = Set<UUID>()
                    for sl in lessons {
                        neededStudentIDs.formUnion(sl.resolvedStudentIDs)
                    }
                    if !neededStudentIDs.isEmpty {
                        let studentsDescriptor = FetchDescriptor<Student>(
                            predicate: #Predicate { neededStudentIDs.contains($0.id) }
                        )
                        let students = try context.fetch(studentsDescriptor)
                        let visibleStudents = TestStudentsFilter.filterVisible(students)
                        let studentsByID = Dictionary(uniqueKeysWithValues: visibleStudents.map { ($0.id, $0) })
                        let filtered = filterByLevelIfNeeded(lessons, studentsByID: studentsByID)
                        if !filtered.isEmpty {
                            return current
                        }
                    } else if levelFilter == .all {
                        // If no students but level filter is "all", still count it
                        return current
                    }
                }
            } catch {
                // If fetch fails, continue to next day
            }
            current = nextSchoolDaySync(after: current)
            // Prevent infinite loop if we've wrapped around
            if current <= date {
                break
            }
        }
        // If no day with lessons found, return the next school day
        return nextSchoolDaySync(after: date)
    }
    
    /// Finds the previous day (before the given date) that has lessons scheduled.
    /// Only considers school days and respects the current level filter.
    func previousDayWithLessons(before date: Date) -> Date {
        var current = previousSchoolDaySync(before: date)
        // Safety cap: search up to 2 years backward
        for _ in 0..<730 {
            let (day, nextDay) = AppCalendar.dayRange(for: current)
            do {
                let descriptor = FetchDescriptor<StudentLesson>(
                    predicate: #Predicate { sl in
                        sl.scheduledForDay >= day && sl.scheduledForDay < nextDay
                    }
                )
                let lessons = try context.fetch(descriptor)
                if !lessons.isEmpty {
                    // Check if any lessons match the level filter
                    var neededStudentIDs = Set<UUID>()
                    for sl in lessons {
                        neededStudentIDs.formUnion(sl.resolvedStudentIDs)
                    }
                    if !neededStudentIDs.isEmpty {
                        let studentsDescriptor = FetchDescriptor<Student>(
                            predicate: #Predicate { neededStudentIDs.contains($0.id) }
                        )
                        let students = try context.fetch(studentsDescriptor)
                        let visibleStudents = TestStudentsFilter.filterVisible(students)
                        let studentsByID = Dictionary(uniqueKeysWithValues: visibleStudents.map { ($0.id, $0) })
                        let filtered = filterByLevelIfNeeded(lessons, studentsByID: studentsByID)
                        if !filtered.isEmpty {
                            return current
                        }
                    } else if levelFilter == .all {
                        // If no students but level filter is "all", still count it
                        return current
                    }
                }
            } catch {
                // If fetch fails, continue to next day
            }
            let prev = previousSchoolDaySync(before: current)
            // Prevent infinite loop if we've wrapped around
            if prev >= date || prev == current {
                break
            }
            current = prev
        }
        // If no day with lessons found, return the previous school day
        return previousSchoolDaySync(before: date)
    }
}

