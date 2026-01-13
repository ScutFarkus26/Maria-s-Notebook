// TodayViewModel.swift
// View model powering the Today hub. Fetches lessons, work contracts, and plan items
// for the selected day. Uses lightweight lookup caches to avoid per-row fetches.

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
        
        // Load attendance
        reloadAttendance(day: day, nextDay: nextDay)

        // Load recent notes and their students
        reloadRecentNotes()
    }
    
    // MARK: - Private Reload Methods
    
    /// Fetches and loads lessons for today, along with their related students and lessons
    private func reloadLessons(day: Date, nextDay: Date) {
        // Fetch lessons for today
        var dayLessons: [StudentLesson] = []
        do {
            let byDayDescriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { sl in
                    sl.scheduledForDay >= day && sl.scheduledForDay < nextDay
                },
                sortBy: []
            )
            dayLessons = try context.fetch(byDayDescriptor)

            // Stable sort
            dayLessons.sort { lhs, rhs in
                if lhs.scheduledForDay != rhs.scheduledForDay {
                    return lhs.scheduledForDay < rhs.scheduledForDay
                }
                switch (lhs.scheduledFor, rhs.scheduledFor) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.createdAt < rhs.createdAt
                }
            }
        } catch {
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
        
        // Only load students not already cached
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
            // Fallback: fetch all if predicate fails (shouldn't happen, but safe)
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
        
        // Only load lessons not already cached
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
            // Fallback: fetch all if predicate fails
            let lessons = context.safeFetch(FetchDescriptor<Lesson>())
            for lesson in lessons where ids.contains(lesson.id) {
                lessonsByID[lesson.id] = lesson
            }
        }
    }

    /// Loads work models, plan items, and processes schedule logic
    private func reloadContracts(day: Date, nextDay: Date) {
        do {
            // ENERGY OPTIMIZATION: Limit work fetch to relevant time window
            // Only fetch work that could be relevant (created or touched in last 90 days)
            // This significantly reduces memory usage and query time
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date().addingTimeInterval(-90*24*3600)
            
            // Fetch Active/Review WorkModels with date filter
            let workDescriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate { w in
                    (w.statusRaw == "active" || w.statusRaw == "review") &&
                    w.createdAt >= cutoffDate
                }
            )
            let workItems = try context.fetch(workDescriptor)
            workByID = Dictionary(uniqueKeysWithValues: workItems.map { ($0.id, $0) })
            
            // Collect student/lesson IDs from work to load only what we need
            var workStudentIDs = Set<UUID>()
            var workLessonIDs = Set<UUID>()
            for work in workItems {
                if let sid = UUID(uuidString: work.studentID) {
                    workStudentIDs.insert(sid)
                }
                if let lid = UUID(uuidString: work.lessonID) {
                    workLessonIDs.insert(lid)
                }
            }
            
            // Load work-related students and lessons if not already loaded
            loadStudentsIfNeeded(ids: workStudentIDs)
            loadLessonsIfNeeded(ids: workLessonIDs)
            
            // Fetch Plan Items for the work we need
            // Fetch all and filter in memory to avoid predicate issues with Set.contains
            let workIDStrings = Set(workItems.map { $0.id.uuidString })
            let allPlanItemsDescriptor = FetchDescriptor<WorkPlanItem>()
            let allPlanItems = try context.fetch(allPlanItemsDescriptor)
            let planItems = allPlanItems.filter { workIDStrings.contains($0.workID) }
            let planItemsByWork = planItems.grouped { CloudKitUUID.uuid(from: $0.workID) ?? UUID() }
            
            // Fetch Notes that have a work relationship matching our work
            // Use work relationship instead of workContractID
            let allNotes = try context.fetch(FetchDescriptor<ScopedNote>())
            // Filter notes that reference our work via work relationship
            let notes = allNotes.filter { note in
                if let work = note.work, workIDStrings.contains(work.id.uuidString) {
                    return true
                }
                // Fallback: check workContractID for legacy notes (during migration)
                if let contractIDString = note.workContractID,
                   workIDStrings.contains(contractIDString) {
                    return true
                }
                return false
            }
            let notesByWork = notes.grouped { 
                if let work = $0.work {
                    return work.id
                }
                // Fallback: use workContractID for legacy notes
                return $0.workContractID.flatMap { UUID(uuidString: $0) } ?? UUID()
            }
            
            // Process work to build schedule items
            let (overdue, today, stale) = processWork(
                workItems: workItems,
                planItemsByWork: planItemsByWork,
                notesByWork: notesByWork
            )
            
            // Sort outputs
            self.overdueSchedule = overdue.sorted { $0.planItem.scheduledDate < $1.planItem.scheduledDate }
            self.todaysSchedule = today.sorted { $0.planItem.scheduledDate < $1.planItem.scheduledDate }
            self.staleFollowUps = stale.sorted { $0.daysSinceTouch > $1.daysSinceTouch } // Most stale first
            
        } catch {
            print("Error fetching work/plans: \(error)")
            self.overdueSchedule = []
            self.todaysSchedule = []
            self.staleFollowUps = []
        }
    }
    
    /// Processes work items to determine overdue, due today, and stale items
    private func processWork(
        workItems: [WorkModel],
        planItemsByWork: [UUID: [WorkPlanItem]],
        notesByWork: [UUID: [ScopedNote]]
    ) -> (overdue: [ContractScheduleItem], today: [ContractScheduleItem], stale: [ContractFollowUpItem]) {
        var newOverdue: [ContractScheduleItem] = []
        var newToday: [ContractScheduleItem] = []
        var newStale: [ContractFollowUpItem] = []
        
        let startToday = Date().startOfDay
        
        for work in workItems {
            // Filter by Level
            if let sid = UUID(uuidString: work.studentID),
               let s = studentsByID[sid],
               !levelFilter.matches(s.level) {
                continue
            }
            
            let workPlans = planItemsByWork[work.id] ?? []
            let workNotes = notesByWork[work.id] ?? []
            
            // Determine Last Meaningful Touch to validate overdue status
            // Use WorkAgingPolicy for WorkModel (uses checkIns, but we can pass notes)
            let checkIns = work.checkIns ?? []
            let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: workNotes)
            let startLastTouch = lastTouch.startOfDay
            
            // Sort plans to find earliest relevant
            let sortedPlans = workPlans.sorted { $0.scheduledDate < $1.scheduledDate }
            
            // --- Overdue Logic ---
            // An item is overdue if its date is < Today AND last touch is BEFORE that date.
            // (i.e., we haven't "addressed" it since it was scheduled)
            var isOverdueOrToday = false
            
            if let overdueItem = sortedPlans.first(where: { item in
                let itemDate = item.scheduledDate.startOfDay
                return itemDate < startToday && startLastTouch < itemDate
            }) {
                newOverdue.append(ContractScheduleItem(work: work, planItem: overdueItem))
                isOverdueOrToday = true
            }
            
            // --- Due Today Logic ---
            // Explicitly scheduled for today
            if let todayItem = sortedPlans.first(where: { $0.scheduledDate.isSameDay(as: Date()) }) {
                newToday.append(ContractScheduleItem(work: work, planItem: todayItem))
                isOverdueOrToday = true
            }
            
            // --- Stale/Follow-Up Logic ---
            // If not explicitly scheduled for today or overdue, check if it's stale (needs follow-up)
            if !isOverdueOrToday {
                if WorkAgingPolicy.isStale(work, modelContext: context, checkIns: checkIns, notes: workNotes) {
                    let days = WorkAgingPolicy.daysSinceLastTouch(for: work, modelContext: context, checkIns: checkIns, notes: workNotes)
                    newStale.append(ContractFollowUpItem(work: work, daysSinceTouch: days))
                }
            }
        }
        
        return (newOverdue, newToday, newStale)
    }
    
    /// Loads completed work items for today
    private func reloadCompletedContracts(day: Date, nextDay: Date) {
        do {
            let descriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate { w in
                    if let ca = w.completedAt {
                        return ca >= day && ca < nextDay
                    } else {
                        return false
                    }
                },
                sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
            )
            let workItems = try context.fetch(descriptor)
            
            completedContracts = workItems.filter { w in
                guard let uuid = UUID(uuidString: w.studentID),
                      let s = self.studentsByID[uuid] else { return false }
                return levelFilter.matches(s.level)
            }
        } catch {
            completedContracts = []
        }
    }
    
    private func reloadReminders(day: Date, nextDay: Date) {
        do {
            let startOfDay = AppCalendar.startOfDay(day)
            
            // Fetch all incomplete reminders (date filtering is done in memory to avoid forced unwraps in predicate)
            let incompleteDescriptor = FetchDescriptor<Reminder>(
                predicate: #Predicate { r in
                    r.isCompleted == false
                }
            )
            let allReminders = try context.fetch(incompleteDescriptor)
            
            // Separate into overdue and due today
            // Overdue = reminders due before the selected date
            // Due today = reminders due on the selected date
            var overdue: [Reminder] = []
            var today: [Reminder] = []
            
            for reminder in allReminders {
                guard let dueDate = reminder.dueDate else { continue }
                // Use AppCalendar for consistent date normalization
                let dueDay = AppCalendar.startOfDay(dueDate)
                
                if dueDay >= startOfDay && dueDay < nextDay {
                    // Due on the selected date
                    today.append(reminder)
                } else if dueDay < startOfDay {
                    // Overdue (before the selected date)
                    overdue.append(reminder)
                }
            }
            
            // Sort by due date
            overdue.sort { ($0.dueDate ?? Date.distantPast) < ($1.dueDate ?? Date.distantPast) }
            today.sort { ($0.dueDate ?? Date.distantPast) < ($1.dueDate ?? Date.distantPast) }
            
            self.overdueReminders = overdue
            self.todaysReminders = today
            
        } catch {
            print("Error loading reminders: \(error)")
            self.overdueReminders = []
            self.todaysReminders = []
        }
    }
    
    private func reloadAttendance(day: Date, nextDay: Date) {
        do {
            let descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { rec in rec.date >= day && rec.date < nextDay },
                sortBy: []
            )
            let records = try context.fetch(descriptor)
            
            // MEMORY OPTIMIZATION: Only load students referenced in attendance records if not already loaded
            // CloudKit compatibility: Convert String studentIDs to UUIDs
            let attendanceStudentIDs = Set(records.compactMap { $0.studentID.asUUID })
            for sid in attendanceStudentIDs where studentsByID[sid] == nil {
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
            var absent = 0
            var leftEarly = 0
            var absentIDs: Set<UUID> = []
            var leftEarlyIDs: Set<UUID> = []
            for rec in records {
                // CloudKit compatibility: Convert String studentID to UUID for lookup
                guard let studentIDUUID = rec.studentID.asUUID,
                      let s = self.studentsByID[studentIDUUID] else { continue }
                if !levelFilter.matches(s.level) { continue }
                switch rec.status {
                case .present, .tardy: present += 1
                case .absent:
                    absent += 1
                    absentIDs.insert(studentIDUUID)
                case .leftEarly:
                    leftEarly += 1
                    leftEarlyIDs.insert(studentIDUUID)
                case .unmarked: break
                }
            }
            attendanceSummary = AttendanceSummary(presentCount: present, absentCount: absent, leftEarlyCount: leftEarly)
            self.absentToday = Array(absentIDs)
            self.leftEarlyToday = Array(leftEarlyIDs)
        } catch {
            attendanceSummary = AttendanceSummary()
            self.absentToday = []
            self.leftEarlyToday = []
        }
    }

    /// Loads recent notes from the last 7 days and their associated students
    private func reloadRecentNotes() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date().addingTimeInterval(-7*24*3600)
        do {
            let descriptor = FetchDescriptor<Note>(
                predicate: #Predicate { $0.createdAt >= cutoff }
            )
            var fetchedNotes = try context.fetch(descriptor)
            fetchedNotes.sort { $0.createdAt > $1.createdAt }
            let limitedNotes = Array(fetchedNotes.prefix(10))
            self.recentNotes = limitedNotes
            
            // Extract all student IDs referenced in these notes
            var noteStudentIDs = Set<UUID>()
            for note in limitedNotes {
                noteStudentIDs.formUnion(studentIDs(for: note))
            }
            
            // Determine missing student IDs that are not in recentNoteStudentsByID
            let missingIDs = noteStudentIDs.subtracting(recentNoteStudentsByID.keys)
            guard !missingIDs.isEmpty else { return }
            
            // Fetch missing students
            let studentsDescriptor = FetchDescriptor<Student>(
                predicate: #Predicate { missingIDs.contains($0.id) }
            )
            let fetchedStudents = try context.fetch(studentsDescriptor)
            for student in fetchedStudents {
                recentNoteStudentsByID[student.id] = student
            }
        } catch {
            self.recentNotes = []
            self.recentNoteStudentsByID = [:]
        }
    }
    
    /// Helper to extract student IDs from a Note's scope
    private func studentIDs(for note: Note) -> [UUID] {
        switch note.scope {
        case .all: return []
        case .student(let id): return [id]
        case .students(let ids): return ids
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
    
    /// Synchronous helper that determines if a date is a non-school day using direct ModelContext fetches.
    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // 1) Explicit non-school day wins
        do {
            let nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            let nonSchoolDays: [NonSchoolDay] = try context.fetch(nsDescriptor)
            if !nonSchoolDays.isEmpty { return true }
        } catch {
            // On fetch error, fall back to weekend logic below
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        // 3) Weekend override makes it a school day
        do {
            let ovDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
            let overrides: [SchoolDayOverride] = try context.fetch(ovDescriptor)
            if !overrides.isEmpty { return false }
        } catch {
            // If override fetch fails, assume weekend remains non-school
        }
        return true
    }
    
    /// Synchronous helper that returns the next school day strictly after the given date.
    private func nextSchoolDaySync(after date: Date) -> Date {
        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the following day
        d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        // Safety cap to avoid infinite loops in case of data errors
        for _ in 0..<730 { // up to ~2 years
            if !isNonSchoolDaySync(d) { return d }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }
    
    /// Synchronous helper that returns the previous school day strictly before the given date.
    private func previousSchoolDaySync(before date: Date) -> Date {
        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the previous day
        d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        for _ in 0..<730 { // up to ~2 years
            if !isNonSchoolDaySync(d) { return d }
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

