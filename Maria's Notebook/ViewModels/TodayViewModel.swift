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
            let normalized = AppCalendar.startOfDay(date)
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
    
    @Published var attendanceSummary: AttendanceSummary = AttendanceSummary()
    @Published var absentToday: [UUID] = []
    @Published var leftEarlyToday: [UUID] = []

    // MARK: - Caches
    @Published private(set) var studentsByID: [UUID: Student] = [:]
    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    // Caching contracts by ID for generic lookups if needed
    @Published private(set) var contractsByID: [UUID: WorkContract] = [:]

    // MARK: - Scheduling
    private var reloadScheduled = false
    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        Task { @MainActor in
            reloadScheduled = false
            reload()
        }
    }

    // MARK: - Init
    init(context: ModelContext, date: Date = Date(), calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
        AppCalendar.adopt(timeZoneFrom: calendar)
        self.date = AppCalendar.startOfDay(date)
        scheduleReload()
    }

    func setCalendar(_ cal: Calendar) {
        self.calendar = cal
        AppCalendar.adopt(timeZoneFrom: cal)
        let normalized = AppCalendar.startOfDay(self.date)
        if self.date != normalized {
            self.date = normalized
        } else {
            scheduleReload()
        }
    }

    // MARK: - Public API
    func reload() {
        let (day, nextDay) = AppCalendar.dayRange(for: date)

        // MEMORY OPTIMIZATION: Fetch lessons for today first, then only load students/lessons we actually need
        
        // 2. Lessons for Today (fetch first to know what we need)
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
        }

        // 1. MEMORY OPTIMIZATION: Only load students and lessons that are actually referenced today
        // Collect IDs from today's lessons
        var neededStudentIDs = Set<UUID>()
        var neededLessonIDs = Set<UUID>()
        
        for sl in dayLessons {
            neededStudentIDs.formUnion(sl.resolvedStudentIDs)
            neededLessonIDs.insert(sl.resolvedLessonID)
        }
        
        // Load only needed students
        var studentsByID: [UUID: Student] = [:]
        if !neededStudentIDs.isEmpty {
            do {
                // Fetch only the students we need
                let studentsDescriptor = FetchDescriptor<Student>(
                    predicate: #Predicate { neededStudentIDs.contains($0.id) }
                )
                let fetchedStudents = try context.fetch(studentsDescriptor)
                let visibleStudents = TestStudentsFilter.filterVisible(fetchedStudents)
                studentsByID = visibleStudents.toDictionary(by: \.id)
            } catch {
                // Fallback: fetch all if predicate fails (shouldn't happen, but safe)
                let allStudents = context.safeFetch(FetchDescriptor<Student>())
                let visibleStudents = TestStudentsFilter.filterVisible(allStudents)
                studentsByID = visibleStudents.toDictionary(by: \.id)
            }
        }
        self.studentsByID = studentsByID
        
        // Load only needed lessons
        var lessonsByID: [UUID: Lesson] = [:]
        if !neededLessonIDs.isEmpty {
            do {
                let lessonsDescriptor = FetchDescriptor<Lesson>(
                    predicate: #Predicate { neededLessonIDs.contains($0.id) }
                )
                let fetchedLessons = try context.fetch(lessonsDescriptor)
                lessonsByID = fetchedLessons.toDictionary(by: \.id)
            } catch {
                // Fallback: fetch all if predicate fails
                let lessons = context.safeFetch(FetchDescriptor<Lesson>())
                lessonsByID = lessons.toDictionary(by: \.id)
            }
        }
        self.lessonsByID = lessonsByID
        
        // Filter today's lessons by level
        todaysLessons = filterByLevelIfNeeded(dayLessons, studentsByID: studentsByID)

        // 3. Work Contracts & Schedule (Replacing WorkCheckIn/WorkModel logic)
        do {
            // Fetch Active/Review Contracts
            let contractsDescriptor = FetchDescriptor<WorkContract>(
                predicate: #Predicate { c in c.statusRaw == "active" || c.statusRaw == "review" }
            )
            let contracts = try context.fetch(contractsDescriptor)
            contractsByID = Dictionary(uniqueKeysWithValues: contracts.map { ($0.id, $0) })
            
            // MEMORY OPTIMIZATION: Collect student/lesson IDs from contracts to load only what we need
            var contractStudentIDs = Set<UUID>()
            var contractLessonIDs = Set<UUID>()
            for contract in contracts {
                if let sid = UUID(uuidString: contract.studentID) {
                    contractStudentIDs.insert(sid)
                }
                if let lid = UUID(uuidString: contract.lessonID) {
                    contractLessonIDs.insert(lid)
                }
            }
            
            // Load contract-related students and lessons if not already loaded
            for sid in contractStudentIDs where studentsByID[sid] == nil {
                if let student = try? context.fetch(FetchDescriptor<Student>(
                    predicate: #Predicate { $0.id == sid }
                )).first {
                    let visible = TestStudentsFilter.filterVisible([student])
                    if let s = visible.first {
                        studentsByID[sid] = s
                    }
                }
            }
            self.studentsByID = studentsByID
            
            for lid in contractLessonIDs where lessonsByID[lid] == nil {
                if let lesson = try? context.fetch(FetchDescriptor<Lesson>(
                    predicate: #Predicate { $0.id == lid }
                )).first {
                    lessonsByID[lid] = lesson
                }
            }
            self.lessonsByID = lessonsByID
            
            // OPTIMIZATION: Only fetch Plan Items for the contracts we need
            // This preserves exact same functionality - we still process all contracts the same way
            let contractIDStrings = Set(contracts.map { $0.id.uuidString })
            let planDescriptor = FetchDescriptor<WorkPlanItem>(
                predicate: #Predicate { contractIDStrings.contains($0.workID) }
            )
            let planItems = try context.fetch(planDescriptor)
            let planItemsByContract = Dictionary(grouping: planItems, by: { UUID(uuidString: $0.workID) ?? UUID() })
            
            // OPTIMIZATION: Only fetch Notes that have a workContractID (not nil)
            // Then filter to only those matching our contracts
            // This preserves exact same functionality - we still get all notes for relevant contracts
            // Reuse contractIDStrings from above (line 250)
            let notesDescriptor = FetchDescriptor<ScopedNote>(
                predicate: #Predicate { note in note.workContractID != nil }
            )
            let allNotesWithContractID = try context.fetch(notesDescriptor)
            // Filter in Swift to only notes for our contracts (SwiftData predicates can't handle Set.contains with optionals)
            let notes = allNotesWithContractID.filter { note in
                guard let contractIDString = note.workContractID else { return false }
                return contractIDStrings.contains(contractIDString)
            }
            let notesByContract = Dictionary(grouping: notes, by: { $0.workContractID.flatMap(UUID.init) ?? UUID() })
            
            var newOverdue: [ContractScheduleItem] = []
            var newToday: [ContractScheduleItem] = []
            var newStale: [ContractFollowUpItem] = []
            
            let startToday = AppCalendar.startOfDay(Date())
            
            // Process Contracts
            for contract in contracts {
                // Filter by Level
                if let sid = UUID(uuidString: contract.studentID),
                   let s = studentsByID[sid],
                   !levelFilter.matches(s.level) {
                    continue
                }
                
                let contractPlans = planItemsByContract[contract.id] ?? []
                let contractNotes = notesByContract[contract.id] ?? []
                
                // Determine Last Meaningful Touch to validate overdue status
                let lastTouch = contract.lastMeaningfulTouchDate(planItems: contractPlans, notes: contractNotes)
                let startLastTouch = AppCalendar.startOfDay(lastTouch)
                
                // Sort plans to find earliest relevant
                let sortedPlans = contractPlans.sorted { $0.scheduledDate < $1.scheduledDate }
                
                // --- Overdue Logic ---
                // An item is overdue if its date is < Today AND last touch is BEFORE that date.
                // (i.e., we haven't "addressed" it since it was scheduled)
                var isOverdueOrToday = false
                
                if let overdueItem = sortedPlans.first(where: { item in
                    let itemDate = AppCalendar.startOfDay(item.scheduledDate)
                    return itemDate < startToday && startLastTouch < itemDate
                }) {
                    newOverdue.append(ContractScheduleItem(contract: contract, planItem: overdueItem))
                    isOverdueOrToday = true
                }
                
                // --- Due Today Logic ---
                // Explicitly scheduled for today
                if let todayItem = sortedPlans.first(where: { AppCalendar.startOfDay($0.scheduledDate) == startToday }) {
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
            
            // Sort outputs
            self.overdueSchedule = newOverdue.sorted { $0.planItem.scheduledDate < $1.planItem.scheduledDate }
            self.todaysSchedule = newToday.sorted { $0.planItem.scheduledDate < $1.planItem.scheduledDate }
            self.staleFollowUps = newStale.sorted { $0.daysSinceTouch > $1.daysSinceTouch } // Most stale first
            
        } catch {
            print("Error fetching contracts/plans: \(error)")
            self.overdueSchedule = []
            self.todaysSchedule = []
            self.staleFollowUps = []
        }

        // 4. Completed Contracts Today (Replaces Legacy Completions)
        do {
            // Predicate: check if completedAt falls within today's range
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
                guard let uuid = UUID(uuidString: c.studentID),
                      let s = self.studentsByID[uuid] else { return false }
                return levelFilter.matches(s.level)
            }
        } catch {
            completedContracts = []
        }

        // 5. Attendance
        reloadAttendance(day: day, nextDay: nextDay)
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
            let attendanceStudentIDs = Set(records.compactMap { UUID(uuidString: $0.studentID) })
            for sid in attendanceStudentIDs where studentsByID[sid] == nil {
                if let student = try? context.fetch(FetchDescriptor<Student>(
                    predicate: #Predicate { $0.id == sid }
                )).first {
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
                guard let studentIDUUID = UUID(uuidString: rec.studentID),
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
