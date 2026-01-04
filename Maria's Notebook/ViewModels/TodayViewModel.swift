// TodayViewModel.swift
// View model powering the Today hub. Fetches lessons, work contracts, and plan items
// for the selected day. Uses lightweight lookup caches to avoid per-row fetches.

import Foundation
import SwiftUI
import SwiftData
import Combine

/// Data structure for a scheduled check-in (explicit WorkPlanItem).
struct ContractScheduleItem: Identifiable {
    let contract: WorkContract
    let planItem: WorkPlanItem
    var id: UUID { planItem.id }
}

/// Data structure for a stale follow-up (implicit WorkContract aging).
struct ContractFollowUpItem: Identifiable {
    let contract: WorkContract
    let daysSinceTouch: Int
    var id: UUID { contract.id }
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
    
    // Replaced legacy WorkCheckIn/WorkModel lists with Contract-based lists
    @Published var overdueSchedule: [ContractScheduleItem] = []
    @Published var todaysSchedule: [ContractScheduleItem] = []
    @Published var staleFollowUps: [ContractFollowUpItem] = []
    
    // Updated: Now holds WorkContract instead of legacy WorkCompletionRecord
    @Published var completedContracts: [WorkContract] = []
    
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
    @Published private(set) var studentsByID: [UUID: Student] = [:]
    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    // Caching contracts by ID for generic lookups if needed
    @Published private(set) var contractsByID: [UUID: WorkContract] = [:]

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

    /// Loads work contracts, plan items, and processes schedule logic
    private func reloadContracts(day: Date, nextDay: Date) {
        do {
            // ENERGY OPTIMIZATION: Limit contract fetch to relevant time window
            // Only fetch contracts that could be relevant (created or touched in last 90 days)
            // This significantly reduces memory usage and query time
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date().addingTimeInterval(-90*24*3600)
            
            // Fetch Active/Review Contracts with date filter
            let contractsDescriptor = FetchDescriptor<WorkContract>(
                predicate: #Predicate { c in
                    (c.statusRaw == "active" || c.statusRaw == "review") &&
                    c.createdAt >= cutoffDate
                }
            )
            let contracts = try context.fetch(contractsDescriptor)
            contractsByID = Dictionary(uniqueKeysWithValues: contracts.map { ($0.id, $0) })
            
            // Collect student/lesson IDs from contracts to load only what we need
            var contractStudentIDs = Set<UUID>()
            var contractLessonIDs = Set<UUID>()
            for contract in contracts {
                if let sid = contract.studentID.asUUID {
                    contractStudentIDs.insert(sid)
                }
                if let lid = contract.lessonID.asUUID {
                    contractLessonIDs.insert(lid)
                }
            }
            
            // Load contract-related students and lessons if not already loaded
            loadStudentsIfNeeded(ids: contractStudentIDs)
            loadLessonsIfNeeded(ids: contractLessonIDs)
            
            // Fetch Plan Items for the contracts we need
            let contractIDStrings = Set(contracts.map { $0.id.uuidString })
            let planDescriptor = FetchDescriptor<WorkPlanItem>(
                predicate: #Predicate { contractIDStrings.contains($0.workID) }
            )
            let planItems = try context.fetch(planDescriptor)
            let planItemsByContract = planItems.grouped { CloudKitUUID.uuid(from: $0.workID) ?? UUID() }
            
            // Fetch Notes that have a workContractID matching our contracts
            let notesDescriptor = FetchDescriptor<ScopedNote>(
                predicate: #Predicate { note in note.workContractID != nil }
            )
            let allNotesWithContractID = try context.fetch(notesDescriptor)
            // Filter in Swift to only notes for our contracts (SwiftData predicates can't handle Set.contains with optionals)
            let notes = allNotesWithContractID.filter { note in
                guard let contractIDString = note.workContractID else { return false }
                return contractIDStrings.contains(contractIDString)
            }
            let notesByContract = notes.grouped { $0.workContractID.flatMap(CloudKitUUID.uuid) ?? UUID() }
            
            // Process contracts to build schedule items
            let (overdue, today, stale) = processContracts(
                contracts: contracts,
                planItemsByContract: planItemsByContract,
                notesByContract: notesByContract
            )
            
            // Sort outputs
            self.overdueSchedule = overdue.sorted { $0.planItem.scheduledDate < $1.planItem.scheduledDate }
            self.todaysSchedule = today.sorted { $0.planItem.scheduledDate < $1.planItem.scheduledDate }
            self.staleFollowUps = stale.sorted { $0.daysSinceTouch > $1.daysSinceTouch } // Most stale first
            
        } catch {
            print("Error fetching contracts/plans: \(error)")
            self.overdueSchedule = []
            self.todaysSchedule = []
            self.staleFollowUps = []
        }
    }
    
    /// Processes contracts to determine overdue, due today, and stale items
    private func processContracts(
        contracts: [WorkContract],
        planItemsByContract: [UUID: [WorkPlanItem]],
        notesByContract: [UUID: [ScopedNote]]
    ) -> (overdue: [ContractScheduleItem], today: [ContractScheduleItem], stale: [ContractFollowUpItem]) {
        var newOverdue: [ContractScheduleItem] = []
        var newToday: [ContractScheduleItem] = []
        var newStale: [ContractFollowUpItem] = []
        
        let startToday = Date().startOfDay
        
        for contract in contracts {
            // Filter by Level
            if let sid = contract.studentID.asUUID,
               let s = studentsByID[sid],
               !levelFilter.matches(s.level) {
                continue
            }
            
            let contractPlans = planItemsByContract[contract.id] ?? []
            let contractNotes = notesByContract[contract.id] ?? []
            
            // Determine Last Meaningful Touch to validate overdue status
            let lastTouch = contract.lastMeaningfulTouchDate(planItems: contractPlans, notes: contractNotes)
            let startLastTouch = lastTouch.startOfDay
            
            // Sort plans to find earliest relevant
            let sortedPlans = contractPlans.sorted { $0.scheduledDate < $1.scheduledDate }
            
            // --- Overdue Logic ---
            // An item is overdue if its date is < Today AND last touch is BEFORE that date.
            // (i.e., we haven't "addressed" it since it was scheduled)
            var isOverdueOrToday = false
            
            if let overdueItem = sortedPlans.first(where: { item in
                let itemDate = item.scheduledDate.startOfDay
                return itemDate < startToday && startLastTouch < itemDate
            }) {
                newOverdue.append(ContractScheduleItem(contract: contract, planItem: overdueItem))
                isOverdueOrToday = true
            }
            
            // --- Due Today Logic ---
            // Explicitly scheduled for today
            if let todayItem = sortedPlans.first(where: { $0.scheduledDate.isSameDay(as: Date()) }) {
                newToday.append(ContractScheduleItem(contract: contract, planItem: todayItem))
                isOverdueOrToday = true
            }
            
            // --- Stale/Follow-Up Logic ---
            // If not explicitly scheduled for today or overdue, check if it's stale (needs follow-up)
            if !isOverdueOrToday {
                if contract.isStale(modelContext: context, planItems: contractPlans, notes: contractNotes) {
                    let days = contract.daysSinceLastTouch(modelContext: context, planItems: contractPlans, notes: contractNotes)
                    newStale.append(ContractFollowUpItem(contract: contract, daysSinceTouch: days))
                }
            }
        }
        
        return (newOverdue, newToday, newStale)
    }
    
    /// Loads completed contracts for today
    private func reloadCompletedContracts(day: Date, nextDay: Date) {
        do {
            let descriptor = FetchDescriptor<WorkContract>(
                predicate: #Predicate { c in
                    if let ca = c.completedAt {
                        return ca >= day && ca < nextDay
                    } else {
                        return false
                    }
                },
                sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
            )
            let contracts = try context.fetch(descriptor)
            
            completedContracts = contracts.filter { c in
                guard let uuid = c.studentID.asUUID,
                      let s = self.studentsByID[uuid] else { return false }
                return levelFilter.matches(s.level)
            }
        } catch {
            completedContracts = []
        }
    }
    
    private func reloadReminders(day: Date, nextDay: Date) {
        do {
            let startOfToday = Date().startOfDay
            let startOfDay = day.startOfDay
            
            // ENERGY OPTIMIZATION: Only fetch reminders that could be relevant
            // Fetch incomplete reminders with due dates in the past or within the next 7 days
            // This avoids loading reminders that are far in the future
            let futureCutoff = Calendar.current.date(byAdding: .day, value: 7, to: startOfDay) ?? nextDay
            let pastCutoff = Calendar.current.date(byAdding: .day, value: -30, to: startOfDay) ?? Date.distantPast
            
            let incompleteDescriptor = FetchDescriptor<Reminder>(
                predicate: #Predicate { r in
                    r.isCompleted == false &&
                    (r.dueDate == nil || (r.dueDate! >= pastCutoff && r.dueDate! <= futureCutoff))
                }
            )
            let allReminders = try context.fetch(incompleteDescriptor)
            
            // Separate into overdue and due today
            var overdue: [Reminder] = []
            var today: [Reminder] = []
            
            for reminder in allReminders {
                guard let dueDate = reminder.dueDate else { continue }
                let dueDay = dueDate.startOfDay
                
                if dueDay < startOfToday {
                    // Overdue
                    overdue.append(reminder)
                } else if dueDay >= startOfDay && dueDay < nextDay {
                    // Due today
                    today.append(reminder)
                }
            }
            
            // Sort by due date
            overdue.sort { ($0.dueDate ?? Date.distantPast) < ($1.dueDate ?? Date.distantPast) }
            today.sort { ($0.dueDate ?? Date.distantPast) < ($1.dueDate ?? Date.distantPast) }
            
            self.overdueReminders = overdue
            self.todaysReminders = today
            
        } catch {
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
    
    /// Finds the next day (after the given date) that has lessons scheduled.
    /// Only considers school days and respects the current level filter.
    func nextDayWithLessons(after date: Date) -> Date {
        var current = SchoolCalendar.nextSchoolDay(after: date, using: context)
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
            current = SchoolCalendar.nextSchoolDay(after: current, using: context)
            // Prevent infinite loop if we've wrapped around
            if current <= date {
                break
            }
        }
        // If no day with lessons found, return the next school day
        return SchoolCalendar.nextSchoolDay(after: date, using: context)
    }
    
    /// Finds the previous day (before the given date) that has lessons scheduled.
    /// Only considers school days and respects the current level filter.
    func previousDayWithLessons(before date: Date) -> Date {
        var current = SchoolCalendar.previousSchoolDay(before: date, using: context)
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
            let prev = SchoolCalendar.previousSchoolDay(before: current, using: context)
            // Prevent infinite loop if we've wrapped around
            if prev >= date || prev == current {
                break
            }
            current = prev
        }
        // If no day with lessons found, return the previous school day
        return SchoolCalendar.previousSchoolDay(before: date, using: context)
    }
}

