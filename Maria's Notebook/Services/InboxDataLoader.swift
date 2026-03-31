import Foundation
import CoreData

/// Reusable data loader for Inbox/Today style views.
/// Provides filtered fetches using NSFetchRequest to avoid loading entire tables.
@MainActor
final class InboxDataLoader {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Main Load Method

    /// Loads all data needed for the Follow-Up Inbox view.
    /// Returns filtered data to minimize memory usage and improve performance.
    func loadInboxData() -> InboxData {
        // Load presented lesson assignments (for lesson follow-ups)
        let presentedLAs = loadPresentedLessonAssignments()

        // Load active/review work models (for work check-ins/reviews)
        let workModels = loadActiveWorkModels()

        // Load check-ins and notes only for the work models we need
        let workIDs = Set(workModels.compactMap(\.id))
        let checkIns = loadCheckIns(for: workIDs)
        let notes = loadNotes(for: workIDs)

        // Collect referenced student and lesson IDs
        var studentIDs = Set<UUID>()
        var lessonIDs = Set<UUID>()

        for la in presentedLAs {
            studentIDs.formUnion(la.studentUUIDs)
            if let lessonUUID = la.lessonIDUUID {
                lessonIDs.insert(lessonUUID)
            }
        }

        for work in workModels {
            if let sid = UUID(uuidString: work.studentID) {
                studentIDs.insert(sid)
            }
            if let lid = UUID(uuidString: work.lessonID) {
                lessonIDs.insert(lid)
            }
        }

        // Load only referenced students and lessons
        let students = loadStudents(ids: studentIDs)
        let lessons = loadLessons(ids: lessonIDs)

        return InboxData(
            lessonAssignments: presentedLAs,
            checkIns: checkIns,
            notes: notes,
            students: students,
            lessons: lessons
        )
    }

    // MARK: - Individual Fetch Methods

    /// Loads lesson assignments that have been presented.
    /// This is the filtered set needed for lesson follow-up calculations.
    func loadPresentedLessonAssignments() -> [CDLessonAssignment] {
        let presentedState = LessonAssignmentState.presented.rawValue
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "stateRaw == %@", presentedState)
        return context.safeFetch(request)
    }

    /// Loads active and review work models (preferred).
    /// This is the filtered set needed for work check-in and review calculations.
    func loadActiveWorkModels() -> [CDWorkModel] {
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "statusRaw == %@ OR statusRaw == %@", activeRaw, reviewRaw)
        return context.safeFetch(request)
    }

    /// Loads scheduled check-ins only for the specified work IDs.
    /// NOTE: Core Data NSPredicate supports IN queries, but for UUID-string matching
    /// we fetch by status and filter in memory for correctness.
    func loadCheckIns(for workIDs: Set<UUID>) -> [CDWorkCheckIn] {
        guard !workIDs.isEmpty else { return [] }

        let workIDStrings = Set(workIDs.map(\.uuidString))
        let scheduledStatus = WorkCheckInStatus.scheduled.rawValue
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = NSPredicate(format: "statusRaw == %@", scheduledStatus)
        request.fetchLimit = 2000 // Safety limit: prevents memory issues with large datasets
        let allItems = context.safeFetch(request)
        return allItems.filter { workIDStrings.contains($0.workID) }
    }

    /// Loads notes only for the specified work IDs.
    func loadNotes(for workIDs: Set<UUID>) -> [CDNote] {
        guard !workIDs.isEmpty else { return [] }

        // PERFORMANCE: Fetch notes with work relationship, then filter in Swift using Set for O(1) lookup
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "work != nil")
        let allNotesWithWork = context.safeFetch(request)

        // workIDs is already a Set, so .contains is O(1)
        return allNotesWithWork.filter { note in
            guard let work = note.work, let wID = work.id else { return false }
            return workIDs.contains(wID)
        }
    }

    /// Loads students by their IDs.
    /// NOTE: Fetches all and filters in memory because student rosters are small.
    func loadStudents(ids: Set<UUID>) -> [CDStudent] {
        guard !ids.isEmpty else { return [] }

        let request = CDFetchRequest(CDStudent.self)
        request.fetchLimit = 500 // Safety limit: reasonable maximum for student roster
        let allStudents = context.safeFetch(request)
        let filtered = allStudents.filter { student in
            guard let sid = student.id else { return false }
            return ids.contains(sid)
        }
        return filtered
    }

    /// Loads lessons by their IDs.
    /// NOTE: Fetches all and filters in memory because lesson libraries are bounded.
    func loadLessons(ids: Set<UUID>) -> [CDLesson] {
        guard !ids.isEmpty else { return [] }

        let request = CDFetchRequest(CDLesson.self)
        request.fetchLimit = 1000 // Safety limit: reasonable maximum for lesson library
        let allLessons = context.safeFetch(request)
        return allLessons.filter { lesson in
            guard let lid = lesson.id else { return false }
            return ids.contains(lid)
        }
    }
}

// MARK: - Data Structure

/// Container for inbox data loaded by InboxDataLoader.
struct InboxData {
    let lessonAssignments: [CDLessonAssignment]
    let checkIns: [CDWorkCheckIn]
    let notes: [CDNote]
    let students: [CDStudent]
    let lessons: [CDLesson]
}
