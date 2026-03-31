import Foundation
import OSLog
import CoreData

// MARK: - Today Data Fetcher

// Service for fetching data needed by TodayViewModel.
// Encapsulates all database fetch operations.
// swiftlint:disable:next type_body_length
enum TodayDataFetcher {

    private static let logger = Logger.app_

    // MARK: - Lesson Fetching

    /// Fetches lessons for a specific day.
    /// Includes lessons scheduled for the day AND lessons presented (presentedAt) on the day,
    /// so that the "Lessons Presented" section shows all presentations regardless of original schedule.
    static func fetchLessons(
        day: Date,
        nextDay: Date,
        context: NSManagedObjectContext
    ) -> [LessonAssignment] {
        do {
            // Fetch lessons scheduled for this day
            let byDayRequest = CDFetchRequest(LessonAssignment.self)
            byDayRequest.predicate = NSPredicate(
                format: "scheduledForDay >= %@ AND scheduledForDay < %@",
                day as NSDate, nextDay as NSDate
            )
            var dayLessons = try context.fetch(byDayRequest)

            // Also fetch lessons that were presented (presentedAt) on this day but not scheduled for it.
            // This catches inbox items or lessons scheduled for other days that were presented today.
            let presentedState = LessonAssignmentState.presented.rawValue
            let presentedRequest = CDFetchRequest(LessonAssignment.self)
            presentedRequest.predicate = NSPredicate(
                format: "stateRaw == %@ AND presentedAt >= %@ AND presentedAt < %@ AND (scheduledForDay < %@ OR scheduledForDay >= %@)",
                presentedState, day as NSDate, nextDay as NSDate,
                day as NSDate, nextDay as NSDate
            )
            let presentedLessons = try context.fetch(presentedRequest)

            // Deduplicate against already-fetched scheduled lessons
            let scheduledIDs = Set(dayLessons.compactMap { $0.id })
            let additionalPresented = presentedLessons.filter { lesson in
                guard let lessonID = lesson.id else { return false }
                return !scheduledIDs.contains(lessonID)
            }
            dayLessons.append(contentsOf: additionalPresented)

            // Stable sort
            dayLessons.sort { lhs, rhs in
                let lhsDay = lhs.scheduledForDay ?? .distantPast
                let rhsDay = rhs.scheduledForDay ?? .distantPast
                if lhsDay != rhsDay {
                    return lhsDay < rhsDay
                }
                switch (lhs.scheduledFor, rhs.scheduledFor) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
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

    // Fetches work models and related data (plan items, notes).
    // swiftlint:disable:next function_body_length
    static func fetchWorkData(
        day: Date,
        nextDay: Date,
        referenceDate: Date,
        context: NSManagedObjectContext
    ) -> WorkFetchResult? {
        do {
            // ENERGY OPTIMIZATION: Limit work fetch to relevant time window
            let actualReferenceDate = max(referenceDate, Date())
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: actualReferenceDate)
                ?? actualReferenceDate.addingTimeInterval(-90*24*3600)

            // Fetch Active/Review WorkModels with date filter
            // PERFORMANCE: Add fetch limit to prevent unbounded result sets
            let workRequest = CDFetchRequest(WorkModel.self)
            workRequest.predicate = NSPredicate(
                format: "(statusRaw == %@ OR statusRaw == %@) AND createdAt >= %@",
                "active", "review", cutoffDate as NSDate
            )
            workRequest.sortDescriptors = [NSSortDescriptor(keyPath: \WorkModel.createdAt, ascending: false)]
            workRequest.fetchLimit = 1000 // Reasonable limit for active work items
            let workItems = try context.fetch(workRequest)

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
            let workIDStrings = Set(workItems.map { $0.id?.uuidString ?? "" }).subtracting([""])

            // Fetch Scheduled Check-Ins (WorkCheckIn with .scheduled status)
            // Migration Note: Uses WorkCheckIn for scheduled check-ins
            let scheduledCheckIns: [WorkCheckIn]
            let scheduledStatus = WorkCheckInStatus.scheduled.rawValue
            if workIDStrings.count > 100 {
                // For large result sets, filter in memory to avoid predicate complexity
                let checkInRequest = CDFetchRequest(WorkCheckIn.self)
                checkInRequest.predicate = NSPredicate(
                    format: "statusRaw == %@ AND date <= %@",
                    scheduledStatus, nextDay as NSDate
                )
                let fetchedCheckIns = try context.fetch(checkInRequest)
                scheduledCheckIns = fetchedCheckIns.filter { workIDStrings.contains($0.workID) }
            } else {
                // For smaller sets, let the predicate handle it
                let checkInRequest = CDFetchRequest(WorkCheckIn.self)
                checkInRequest.predicate = NSPredicate(
                    format: "statusRaw == %@ AND workID IN %@",
                    scheduledStatus, Array(workIDStrings)
                )
                scheduledCheckIns = try context.fetch(checkInRequest)
            }

            // Fetch Notes
            let notesCutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date())
                ?? Date().addingTimeInterval(-90*24*3600)
            // PERFORMANCE: Add fetch limit and sort to prevent unbounded result sets
            let notesRequest = CDFetchRequest(Note.self)
            notesRequest.predicate = NSPredicate(
                format: "createdAt >= %@ AND work != nil",
                notesCutoffDate as NSDate
            )
            notesRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)]
            notesRequest.fetchLimit = 500 // Reasonable limit for recent notes
            let fetchedNotes = try context.fetch(notesRequest)

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
                if let work = note.work, let workID = work.id, workIDStrings.contains(workID.uuidString) {
                    notesByWork[workID, default: []].append(note)
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
        context: NSManagedObjectContext
    ) -> [WorkModel] {
        do {
            let request = CDFetchRequest(WorkModel.self)
            request.predicate = NSPredicate(
                format: "completedAt >= %@ AND completedAt < %@",
                day as NSDate, nextDay as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkModel.completedAt, ascending: false)]
            // OPTIMIZATION: Limit to 100 most recent completed items for performance
            request.fetchLimit = 100
            return try context.fetch(request)
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
        context: NSManagedObjectContext
    ) -> ReminderFetchResult {
        do {
            let startOfDay = AppCalendar.startOfDay(day)

            // Get the configured sync list identifier
            guard let syncListIdentifier = ReminderSyncService.shared.syncListIdentifier else {
                return ReminderFetchResult(overdue: [], today: [], anytime: [])
            }

            // Only fetch incomplete reminders from the configured list
            let incompleteRequest = CDFetchRequest(Reminder.self)
            incompleteRequest.predicate = NSPredicate(
                format: "isCompleted == NO AND eventKitCalendarID == %@",
                syncListIdentifier
            )
            let allReminders = try context.fetch(incompleteRequest)

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
        context: NSManagedObjectContext
    ) -> [CalendarEvent] {
        do {
            let request = CDFetchRequest(CalendarEvent.self)
            request.predicate = NSPredicate(
                format: "startDate < %@ AND endDate > %@",
                nextDay as NSDate, day as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CalendarEvent.startDate, ascending: true)]
            return try context.fetch(request)
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
        context: NSManagedObjectContext
    ) -> AttendanceFetchResult {
        do {
            let request = CDFetchRequest(AttendanceRecord.self)
            request.predicate = NSPredicate(
                format: "date >= %@ AND date < %@",
                day as NSDate, nextDay as NSDate
            )
            let records = try context.fetch(request)
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
    static func fetchRecentNotes(context: NSManagedObjectContext) -> RecentNotesFetchResult {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())
            ?? Date().addingTimeInterval(-7*24*3600)
        do {
            let request = CDFetchRequest(Note.self)
            request.predicate = NSPredicate(format: "createdAt >= %@", cutoff as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)]
            request.fetchLimit = 10
            let fetchedNotes = try context.fetch(request)

            var noteStudentIDs = Set<UUID>()
            for note in fetchedNotes {
                noteStudentIDs.formUnion(studentIDs(for: note))
            }

            return RecentNotesFetchResult(notes: fetchedNotes, neededStudentIDs: noteStudentIDs)
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
