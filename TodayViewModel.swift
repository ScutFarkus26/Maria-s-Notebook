import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class TodayViewModel: ObservableObject {
    // MARK: - Types
    struct AttendanceSummary {
        var presentCount: Int = 0 // Present + Tardy
        var absentCount: Int = 0
        var leftEarlyCount: Int = 0
    }

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

#if DEBUG
    // Lightweight debug logging for TodayViewModel
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f
    }()
    private func fmt(_ d: Date?) -> String {
        guard let d = d else { return "nil" }
        if d == Date.distantPast { return "distantPast" }
        return TodayViewModel.iso.string(from: d)
    }
    private func dbg(_ s: @autoclosure () -> String) {
        print("[Today]", s())
    }
#endif

    // MARK: - Dependencies
    private let context: ModelContext
    private var calendar: Calendar

    // MARK: - Inputs
    @Published var date: Date {
        didSet {
            let normalized = calendar.startOfDay(for: date)
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
    @Published var overdueCheckIns: [WorkCheckIn] = []
    @Published var todaysCheckIns: [WorkCheckIn] = []
    @Published var inProgressWork: [WorkModel] = []
    @Published var completedToday: [WorkCompletionRecord] = []
    @Published var attendanceSummary: AttendanceSummary = AttendanceSummary()

    // Lightweight lookup caches for rows (avoid per-row fetches)
    @Published private(set) var studentsByID: [UUID: Student] = [:]
    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    @Published private(set) var worksByID: [UUID: WorkModel] = [:]
    @Published private(set) var studentLessonsByID: [UUID: StudentLesson] = [:]

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
        self.date = calendar.startOfDay(for: date)
        scheduleReload()
    }

    func setCalendar(_ cal: Calendar) {
        self.calendar = cal
        let normalized = cal.startOfDay(for: self.date)
        if self.date != normalized {
            self.date = normalized
        } else {
            scheduleReload()
        }
    }

    // MARK: - Public API
    func reload() {
        let cal = calendar
        let day = cal.startOfDay(for: date)
        let nextDay = cal.date(byAdding: .day, value: 1, to: day) ?? day

#if DEBUG
        dbg("tz=\(cal.timeZone.identifier) date=\(fmt(self.date)) day=\(fmt(day)) next=\(fmt(nextDay)) level=\(levelFilter.rawValue)")
#endif

        // Build lookup caches first
        let students = (try? context.fetch(FetchDescriptor<Student>())) ?? []
        studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        let lessons = (try? context.fetch(FetchDescriptor<Lesson>())) ?? []
        lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        let allWorks = (try? context.fetch(FetchDescriptor<WorkModel>())) ?? []
        worksByID = Dictionary(uniqueKeysWithValues: allWorks.map { ($0.id, $0) })
        let allStudentLessons = (try? context.fetch(FetchDescriptor<StudentLesson>())) ?? []
        studentLessonsByID = Dictionary(uniqueKeysWithValues: allStudentLessons.map { ($0.id, $0) })

#if DEBUG
        dbg("caches: students=\(studentsByID.count) lessons=\(lessonsByID.count) works=\(worksByID.count) sls=\(studentLessonsByID.count)")
        let slAllCount = studentLessonsByID.count
        if slAllCount > 0 {
            let sample = Array(studentLessonsByID.values.prefix(5))
            for sl in sample {
                dbg("sample sl=\(sl.id) scheduledForDay=\(fmt(sl.scheduledForDay)) scheduledFor=\(fmt(sl.scheduledFor)) isGiven=\(sl.isGiven)")
            }
        }
#endif

        // Lessons scheduled for today — fetch by denormalized day and by exact scheduled time separately,
        // then merge to avoid optional/OR predicate pitfalls.
        do {
            let byDayDescriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { sl in
                    sl.scheduledForDay >= day && sl.scheduledForDay < nextDay
                },
                sortBy: []
            )
            var lessons = try context.fetch(byDayDescriptor)

#if DEBUG
            dbg("byDay=\(lessons.count)")
#endif

            // Stable sort: by scheduledForDay, then scheduledFor (if available), then createdAt
            lessons.sort { lhs, rhs in
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

            todaysLessons = filterByLevelIfNeeded(lessons, studentsByID: self.studentsByID)

#if DEBUG
            dbg("todaysLessons after filter=\(todaysLessons.count)")
#endif
        } catch {
#if DEBUG
            dbg("fetch error: \(error)")
#endif
            // Fallback: filter in-memory if predicate fetch fails (e.g., schema mismatch during migration)
            let inMem = allStudentLessons.filter { sl in
                let sfd = sl.scheduledForDay
                let sf = sl.scheduledFor
                // Include if denormalized day matches or exact scheduled time is in the window
                let matchesDay = (sfd >= day && sfd < nextDay)
                let matchesExact = {
                    if let dt = sf { return dt >= day && dt < nextDay } else { return false }
                }()
                return matchesDay || matchesExact
            }
#if DEBUG
            dbg("fallback in-mem matched=\(inMem.count)")
#endif
            todaysLessons = filterByLevelIfNeeded(inMem, studentsByID: self.studentsByID)
        }

        // Check-ins
        do {
            let overdueDescriptor = FetchDescriptor<WorkCheckIn>(
                predicate: #Predicate { ci in ci.date < day },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            let todayDescriptor = FetchDescriptor<WorkCheckIn>(
                predicate: #Predicate { ci in ci.date >= day && ci.date < nextDay },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            let overdueAll = try context.fetch(overdueDescriptor)
            let todayAll = try context.fetch(todayDescriptor)
            let overdueScheduled = overdueAll.filter { $0.status == .scheduled }
            let todayScheduled = todayAll.filter { $0.status == .scheduled }
            overdueCheckIns = filterCheckInsByLevelIfNeeded(overdueScheduled, studentsByID: self.studentsByID)
            todaysCheckIns = filterCheckInsByLevelIfNeeded(todayScheduled, studentsByID: self.studentsByID)
        } catch {
            overdueCheckIns = []
            todaysCheckIns = []
        }

        // Follow-ups due (open follow-up work where the next scheduled check-in is overdue or today)
        do {
            let descriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate { w in w.completedAt == nil },
                sortBy: []
            )
            let allOpen = try context.fetch(descriptor)
            // Only follow-ups
            let followUps = allOpen.filter { $0.workType == .followUp }
            // Compute next scheduled check-in per work
            let dueFollowUps: [(work: WorkModel, nextDate: Date)] = followUps.compactMap { w in
                let next = w.checkIns
                    .filter { $0.status == .scheduled }
                    .min(by: { $0.date < $1.date })
                if let next, next.date < nextDay {
                    return (w, next.date)
                }
                return nil
            }
            // Apply level filter, preserving nextDate pairing
            let filteredDue = dueFollowUps.filter { pair in
                filterWorksByLevelIfNeeded([pair.work], studentsByID: self.studentsByID).count > 0
            }
            // Sort by next due date ascending; tie-breaker by createdAt descending to match prior feel
            let sorted = filteredDue.sorted { lhs, rhs in
                if lhs.nextDate != rhs.nextDate { return lhs.nextDate < rhs.nextDate }
                return lhs.work.createdAt > rhs.work.createdAt
            }
            inProgressWork = sorted.map { $0.work }
        } catch {
            inProgressWork = []
        }

        // Completions today
        do {
            let descriptor = FetchDescriptor<WorkCompletionRecord>(
                predicate: #Predicate { rc in rc.completedAt >= day && rc.completedAt < nextDay },
                sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
            )
            let all = try context.fetch(descriptor)
            completedToday = all.filter { rc in
                guard let s = self.studentsByID[rc.studentID] else { return false }
                return levelFilter.matches(s.level)
            }
        } catch {
            completedToday = []
        }

        // Attendance summary for the day
        do {
            let descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { rec in rec.date >= day && rec.date < nextDay },
                sortBy: []
            )
            let records = try context.fetch(descriptor)
            var present = 0
            var absent = 0
            var leftEarly = 0
            for rec in records {
                if let s = self.studentsByID[rec.studentID], !levelFilter.matches(s.level) { continue }
                switch rec.status {
                case .present, .tardy: present += 1
                case .absent: absent += 1
                case .leftEarly: leftEarly += 1
                case .unmarked: break
                }
            }
            attendanceSummary = AttendanceSummary(presentCount: present, absentCount: absent, leftEarlyCount: leftEarly)
        } catch {
            attendanceSummary = AttendanceSummary()
        }
    }

    // MARK: - Helpers
    private func filterByLevelIfNeeded(_ lessons: [StudentLesson], studentsByID: [UUID: Student]) -> [StudentLesson] {
        guard levelFilter != .all else { return lessons }
        return lessons.filter { sl in
            let ids = sl.resolvedStudentIDs
            // If no students are attached, keep it visible under any filter
            if ids.isEmpty { return true }

            var anyKnownStudent = false
            for sid in ids {
                if let s = studentsByID[sid] {
                    anyKnownStudent = true
                    if levelFilter.matches(s.level) { return true }
                }
            }
            // If none of the students could be resolved from cache, do not drop the lesson
            return !anyKnownStudent
        }
    }

    private func filterCheckInsByLevelIfNeeded(_ items: [WorkCheckIn], studentsByID: [UUID: Student]) -> [WorkCheckIn] {
        guard levelFilter != .all else { return items }
        // Map WorkModel.id -> participants
        let participantsByWorkID: [UUID: [UUID]] = Dictionary(uniqueKeysWithValues: worksByID.map { ($0.key, $0.value.participants.map { $0.studentID }) })
        return items.filter { ci in
            guard let p = participantsByWorkID[ci.workID] else { return false }
            for sid in p { if let s = studentsByID[sid], levelFilter.matches(s.level) { return true } }
            return false
        }
    }

    private func filterWorksByLevelIfNeeded(_ works: [WorkModel], studentsByID: [UUID: Student]) -> [WorkModel] {
        guard levelFilter != .all else { return works }
        return works.filter { w in
            for p in w.participants { if let s = studentsByID[p.studentID], levelFilter.matches(s.level) { return true } }
            return false
        }
    }
}

