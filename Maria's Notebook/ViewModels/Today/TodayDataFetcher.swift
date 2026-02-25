import Foundation
import OSLog
import SwiftData

// MARK: - Today Data Fetcher

/// Service for fetching data needed by TodayViewModel.
/// Encapsulates all database fetch operations.
enum TodayDataFetcher {

    private static let logger = Logger.app_

    // MARK: - Lesson Fetching

    /// Fetches lessons for a specific day.
    /// Includes lessons scheduled for the day AND lessons presented (givenAt) on the day,
    /// so that the "Lessons Presented" section shows all presentations regardless of original schedule.
    static func fetchLessons(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> [StudentLesson] {
        do {
            // Fetch lessons scheduled for this day
            let byDayDescriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { sl in
                    sl.scheduledForDay >= day && sl.scheduledForDay < nextDay
                },
                sortBy: []
            )
            var dayLessons = try context.fetch(byDayDescriptor)

            // Also fetch lessons that were presented (givenAt) on this day but not scheduled for it.
            // This catches inbox items or lessons scheduled for other days that were presented today.
            let presentedDescriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { sl in
                    if let givenAt = sl.givenAt {
                        return sl.isPresented == true &&
                            givenAt >= day && givenAt < nextDay &&
                            (sl.scheduledForDay < day || sl.scheduledForDay >= nextDay)
                    } else {
                        return false
                    }
                },
                sortBy: []
            )
            let presentedLessons = try context.fetch(presentedDescriptor)

            // Deduplicate against already-fetched scheduled lessons
            let scheduledIDs = Set(dayLessons.map { $0.id })
            let additionalPresented = presentedLessons.filter { !scheduledIDs.contains($0.id) }
            dayLessons.append(contentsOf: additionalPresented)

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
        let checkInsByWork: [UUID: [WorkCheckIn]]
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
            // PERFORMANCE: Add fetch limit to prevent unbounded result sets
            var workDescriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate { w in
                    (w.statusRaw == "active" || w.statusRaw == "review") &&
                    w.createdAt >= cutoffDate
                },
                sortBy: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]
            )
            workDescriptor.fetchLimit = 1000 // Reasonable limit for active work items
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

            // PERFORMANCE: Build workIDStrings Set once for efficient lookups
            let workIDStrings = Set(workItems.map { $0.id.uuidString })
            
            // Fetch Scheduled Check-Ins (WorkCheckIn with .scheduled status)
            // Migration Note: Uses WorkCheckIn for scheduled check-ins
            let scheduledCheckIns: [WorkCheckIn]
            let scheduledStatus = WorkCheckInStatus.scheduled.rawValue
            if workIDStrings.count > 100 {
                // For large result sets, filter in memory to avoid predicate complexity
                let checkInDescriptor = FetchDescriptor<WorkCheckIn>(
                    predicate: #Predicate<WorkCheckIn> { checkIn in
                        checkIn.statusRaw == scheduledStatus &&
                        checkIn.date <= nextDay
                    }
                )
                let fetchedCheckIns = try context.fetch(checkInDescriptor)
                scheduledCheckIns = fetchedCheckIns.filter { workIDStrings.contains($0.workID) }
            } else {
                // For smaller sets, let the predicate handle it
                let checkInDescriptor = FetchDescriptor<WorkCheckIn>(
                    predicate: #Predicate<WorkCheckIn> { checkIn in
                        checkIn.statusRaw == scheduledStatus &&
                        workIDStrings.contains(checkIn.workID)
                    }
                )
                scheduledCheckIns = try context.fetch(checkInDescriptor)
            }

            // Fetch Notes
            let notesCutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date())
                ?? Date().addingTimeInterval(-90*24*3600)
            // PERFORMANCE: Add fetch limit and sort to prevent unbounded result sets
            var notesDescriptor = FetchDescriptor<Note>(
                predicate: #Predicate<Note> { note in
                    note.createdAt >= notesCutoffDate && note.work != nil
                },
                sortBy: [SortDescriptor(\Note.createdAt, order: .reverse)]
            )
            notesDescriptor.fetchLimit = 500 // Reasonable limit for recent notes
            let fetchedNotes = try context.fetch(notesDescriptor)
            
            // PERFORMANCE: Filter notes and group both checkIns and notes in a single pass
            // This reduces iterations from 3 separate loops to 1
            var checkInsByWork: [UUID: [WorkCheckIn]] = [:]
            var notesByWork: [UUID: [Note]] = [:]
            
            for checkIn in scheduledCheckIns {
                if let workID = UUID(uuidString: checkIn.workID) {
                    checkInsByWork[workID, default: []].append(checkIn)
                }
            }
            
            for note in fetchedNotes {
                if let work = note.work, workIDStrings.contains(work.id.uuidString) {
                    notesByWork[work.id, default: []].append(note)
                }
            }

            return WorkFetchResult(
                workItems: workItems,
                checkInsByWork: checkInsByWork,
                notesByWork: notesByWork,
                neededStudentIDs: workStudentIDs,
                neededLessonIDs: workLessonIDs
            )
        } catch {
            logger.error("Error fetching work/plans: \(error)")
            return nil
        }
    }

    // MARK: - Completed Work Fetching

    /// Fetches completed work items for a specific day.
    /// PERFORMANCE: Limited to 100 most recent items to prevent unbounded result sets.
    static func fetchCompletedWork(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> [WorkModel] {
        do {
            var descriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate { w in
                    if let ca = w.completedAt {
                        return ca >= day && ca < nextDay
                    } else {
                        return false
                    }
                },
                sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
            )
            // OPTIMIZATION: Limit to 100 most recent completed items for performance
            descriptor.fetchLimit = 100
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
    /// Only fetches reminders from the currently configured sync list.
    @MainActor static func fetchReminders(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> ReminderFetchResult {
        do {
            let startOfDay = AppCalendar.startOfDay(day)

            // Get the configured sync list identifier
            let syncListIdentifier = ReminderSyncService.shared.syncListIdentifier

            // Only fetch incomplete reminders from the configured list
            let incompleteDescriptor = FetchDescriptor<Reminder>(
                predicate: #Predicate { r in
                    r.isCompleted == false && r.eventKitCalendarID == syncListIdentifier
                }
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
            logger.error("Error loading reminders: \(error)")
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
            logger.error("Error loading calendar events: \(error)")
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
