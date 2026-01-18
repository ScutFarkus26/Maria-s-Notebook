import Foundation
import SwiftData

// MARK: - Today Data Fetcher

/// Service for fetching data needed by TodayViewModel.
/// Encapsulates all database fetch operations.
enum TodayDataFetcher {

    // MARK: - Lesson Fetching

    /// Fetches lessons for a specific day.
    static func fetchLessons(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> [StudentLesson] {
        do {
            let byDayDescriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { sl in
                    sl.scheduledForDay >= day && sl.scheduledForDay < nextDay
                },
                sortBy: []
            )
            var dayLessons = try context.fetch(byDayDescriptor)

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

            return dayLessons
        } catch {
            return []
        }
    }

    // MARK: - Work Fetching

    /// Result of fetching work data.
    struct WorkFetchResult {
        let workItems: [WorkModel]
        let planItemsByWork: [UUID: [WorkPlanItem]]
        let notesByWork: [UUID: [Note]]
        let neededStudentIDs: Set<UUID>
        let neededLessonIDs: Set<UUID>
    }

    /// Fetches work models and related data (plan items, notes).
    static func fetchWorkData(
        day: Date,
        nextDay: Date,
        referenceDate: Date,
        context: ModelContext
    ) -> WorkFetchResult? {
        do {
            // ENERGY OPTIMIZATION: Limit work fetch to relevant time window
            let actualReferenceDate = max(referenceDate, Date())
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: actualReferenceDate)
                ?? actualReferenceDate.addingTimeInterval(-90*24*3600)

            // Fetch Active/Review WorkModels with date filter
            let workDescriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate { w in
                    (w.statusRaw == "active" || w.statusRaw == "review") &&
                    w.createdAt >= cutoffDate
                }
            )
            let workItems = try context.fetch(workDescriptor)

            // Collect student/lesson IDs from work
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

            // Fetch Plan Items
            let workIDStrings = Set(workItems.map { $0.id.uuidString })
            let planItems: [WorkPlanItem]
            if workIDStrings.count > 100 {
                let planDescriptor = FetchDescriptor<WorkPlanItem>(
                    predicate: #Predicate<WorkPlanItem> { item in
                        item.scheduledDate <= nextDay
                    }
                )
                let fetchedPlanItems = try context.fetch(planDescriptor)
                planItems = fetchedPlanItems.filter { workIDStrings.contains($0.workID) }
            } else {
                let planDescriptor = FetchDescriptor<WorkPlanItem>(
                    predicate: #Predicate<WorkPlanItem> { item in
                        workIDStrings.contains(item.workID)
                    }
                )
                planItems = try context.fetch(planDescriptor)
            }
            let planItemsByWork = planItems.grouped { CloudKitUUID.uuid(from: $0.workID) ?? UUID() }

            // Fetch Notes
            let notesCutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date())
                ?? Date().addingTimeInterval(-90*24*3600)
            let notesDescriptor = FetchDescriptor<Note>(
                predicate: #Predicate<Note> { note in
                    note.createdAt >= notesCutoffDate && note.work != nil
                }
            )
            let fetchedNotes = try context.fetch(notesDescriptor)
            let notes = fetchedNotes.filter { note in
                if let work = note.work, workIDStrings.contains(work.id.uuidString) {
                    return true
                }
                return false
            }
            let notesByWork = notes.grouped { $0.work?.id ?? UUID() }

            return WorkFetchResult(
                workItems: workItems,
                planItemsByWork: planItemsByWork,
                notesByWork: notesByWork,
                neededStudentIDs: workStudentIDs,
                neededLessonIDs: workLessonIDs
            )
        } catch {
            #if DEBUG
            print("Error fetching work/plans: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Completed Work Fetching

    /// Fetches completed work items for a specific day.
    static func fetchCompletedWork(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> [WorkModel] {
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
            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }

    // MARK: - Reminder Fetching

    /// Result of fetching reminders.
    struct ReminderFetchResult {
        let overdue: [Reminder]
        let today: [Reminder]
        let anytime: [Reminder]
    }

    /// Fetches and categorizes reminders.
    static func fetchReminders(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> ReminderFetchResult {
        do {
            let startOfDay = AppCalendar.startOfDay(day)

            let incompleteDescriptor = FetchDescriptor<Reminder>(
                predicate: #Predicate { r in r.isCompleted == false }
            )
            let allReminders = try context.fetch(incompleteDescriptor)

            var overdue: [Reminder] = []
            var today: [Reminder] = []
            var anytime: [Reminder] = []

            for reminder in allReminders {
                guard let dueDate = reminder.dueDate else {
                    anytime.append(reminder)
                    continue
                }
                let dueDay = AppCalendar.startOfDay(dueDate)

                if dueDay >= startOfDay && dueDay < nextDay {
                    today.append(reminder)
                } else if dueDay < startOfDay {
                    overdue.append(reminder)
                }
            }

            overdue.sort { ($0.dueDate ?? Date.distantPast) < ($1.dueDate ?? Date.distantPast) }
            today.sort { ($0.dueDate ?? Date.distantPast) < ($1.dueDate ?? Date.distantPast) }
            anytime.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

            return ReminderFetchResult(overdue: overdue, today: today, anytime: anytime)
        } catch {
            #if DEBUG
            print("Error loading reminders: \(error)")
            #endif
            return ReminderFetchResult(overdue: [], today: [], anytime: [])
        }
    }

    // MARK: - Calendar Event Fetching

    /// Fetches calendar events that overlap with a specific day.
    static func fetchCalendarEvents(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> [CalendarEvent] {
        do {
            let descriptor = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { event in
                    event.startDate < nextDay && event.endDate > day
                },
                sortBy: [SortDescriptor(\CalendarEvent.startDate)]
            )
            return try context.fetch(descriptor)
        } catch {
            #if DEBUG
            print("Error loading calendar events: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Attendance Fetching

    /// Result of fetching attendance data.
    struct AttendanceFetchResult {
        let records: [AttendanceRecord]
        let neededStudentIDs: Set<UUID>
    }

    /// Fetches attendance records for a specific day.
    static func fetchAttendance(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> AttendanceFetchResult {
        do {
            let descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { rec in rec.date >= day && rec.date < nextDay },
                sortBy: []
            )
            let records = try context.fetch(descriptor)
            let studentIDs = Set(records.compactMap { $0.studentID.asUUID })
            return AttendanceFetchResult(records: records, neededStudentIDs: studentIDs)
        } catch {
            return AttendanceFetchResult(records: [], neededStudentIDs: [])
        }
    }

    // MARK: - Recent Notes Fetching

    /// Result of fetching recent notes.
    struct RecentNotesFetchResult {
        let notes: [Note]
        let neededStudentIDs: Set<UUID>
    }

    /// Fetches recent notes from the last 7 days.
    static func fetchRecentNotes(context: ModelContext) -> RecentNotesFetchResult {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())
            ?? Date().addingTimeInterval(-7*24*3600)
        do {
            let descriptor = FetchDescriptor<Note>(
                predicate: #Predicate { $0.createdAt >= cutoff }
            )
            var fetchedNotes = try context.fetch(descriptor)
            fetchedNotes.sort { $0.createdAt > $1.createdAt }
            let limitedNotes = Array(fetchedNotes.prefix(10))

            var noteStudentIDs = Set<UUID>()
            for note in limitedNotes {
                noteStudentIDs.formUnion(studentIDs(for: note))
            }

            return RecentNotesFetchResult(notes: limitedNotes, neededStudentIDs: noteStudentIDs)
        } catch {
            return RecentNotesFetchResult(notes: [], neededStudentIDs: [])
        }
    }

    // MARK: - Private Helpers

    /// Extracts student IDs from a Note's scope.
    private static func studentIDs(for note: Note) -> [UUID] {
        switch note.scope {
        case .all: return []
        case .student(let id): return [id]
        case .students(let ids): return ids
        }
    }
}
