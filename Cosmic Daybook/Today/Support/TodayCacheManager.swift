import Foundation
import CoreData

// MARK: - Today Cache Manager

/// Manager for caching students, lessons, and work data in TodayViewModel.
/// Provides efficient lookup dictionaries and lazy computation of derived values.
final class TodayCacheManager {

    // MARK: - Cached Data

    private(set) var studentsByID: [UUID: CDStudent] = [:]
    private(set) var lessonsByID: [UUID: CDLesson] = [:]
    private(set) var workByID: [UUID: CDWorkModel] = [:]

    // MARK: - Initialization

    init() {}

    // MARK: - Update Methods

    /// Updates the work cache with new values.
    func updateWork(_ work: [UUID: CDWorkModel]) {
        workByID = work
    }

    // MARK: - Display Name Helpers

    /// Returns the canonical short name ("Maya S") for a student ID.
    func displayName(for studentID: UUID) -> String {
        guard let student = studentsByID[studentID] else { return "Student" }
        return student.shortName
    }

    /// Returns the lesson name for a lesson ID.
    func lessonName(for lessonID: UUID) -> String {
        lessonsByID[lessonID]?.name ?? "Lesson"
    }

    // MARK: - Roster Snapshot

    /// Every student row from the last whole-table read. Lookups that miss
    /// the enrolled cache — departed children, hidden test students, ids with
    /// no row — resolve against it, so a miss no longer re-reads the table on
    /// every call (it did about five times a reload, plus once each for the
    /// recent notes and the departed children). Dropped when a student or
    /// lesson changes (`missInputs`).
    private var roster: [CDStudent]?
    /// Lesson ids looked up and not found, kept on the same terms.
    private var missingLessonIDs: Set<UUID> = []
    /// Flips when a student or lesson changes; made on first use.
    private var missInputs: ManagedObjectChangeFlag?
    /// Whole-table student or lesson reads made so far (for tests pinning
    /// the miss caching).
    private(set) var tableFetchCount = 0

    nonisolated static let missInputEntities: Set<String> = ["Student", "Lesson"]

    /// Forgets the roster snapshot and the lesson misses when a student or
    /// lesson changed since they were read.
    private func dropMissesIfInputsMoved(context: NSManagedObjectContext) {
        let flag: ManagedObjectChangeFlag
        if let existing = missInputs, existing.watches(context) {
            flag = existing
        } else {
            flag = ManagedObjectChangeFlag(
                entityNames: Self.missInputEntities, context: context, listensForImportSignal: false
            )
            missInputs = flag
        }
        if flag.consume(pendingIn: context) {
            roster = nil
            missingLessonIDs.removeAll()
        }
    }

    /// The roster snapshot, read from the store only when there is none.
    private func rosterRows(context: NSManagedObjectContext) -> [CDStudent] {
        dropMissesIfInputsMoved(context: context)
        if let roster { return roster }
        let request = CDFetchRequest(CDStudent.self)
        request.fetchLimit = 500 // Safety limit for student roster
        let rows = context.safeFetch(request)
        roster = rows
        tableFetchCount += 1
        return rows
    }

    /// Enrolled students among `ids`, hidden test students included (the
    /// recent-notes rows name them).
    func enrolledStudents(ids: Set<UUID>, context: NSManagedObjectContext) -> [UUID: CDStudent] {
        guard !ids.isEmpty else { return [:] }
        var byID: [UUID: CDStudent] = [:]
        for student in rosterRows(context: context).filterEnrolled() {
            guard let id = student.id, ids.contains(id) else { continue }
            byID[id] = student
        }
        return byID
    }

    /// Every former student — withdrawn or transferred — keyed by id.
    func departedStudents(context: NSManagedObjectContext) -> [UUID: CDStudent] {
        TodayFollowUpLoader.departedStudents(in: rosterRows(context: context))
    }

    // MARK: - Loading Methods

    /// Loads students if not already cached. Only enrolled, visible students
    /// are cached; the rest resolve against the roster snapshot each time.
    func loadStudentsIfNeeded(ids: Set<UUID>, context: NSManagedObjectContext) {
        guard !ids.isEmpty else { return }

        let missingIDSet = ids.filter { studentsByID[$0] == nil }
        guard !missingIDSet.isEmpty else { return }

        let filtered = rosterRows(context: context).filterEnrolled().filter { student in
            guard let studentID = student.id else { return false }
            return missingIDSet.contains(studentID)
        }
        let visibleStudents = TestStudentsFilter.filterVisible(filtered)

        for student in visibleStudents {
            if let studentID = student.id {
                studentsByID[studentID] = student
            }
        }
    }

    /// Loads lessons if not already cached. An id with no lesson is
    /// remembered, so it does not re-read the table until a lesson changes.
    func loadLessonsIfNeeded(ids: Set<UUID>, context: NSManagedObjectContext) {
        guard !ids.isEmpty else { return }

        guard ids.contains(where: { lessonsByID[$0] == nil }) else { return }
        dropMissesIfInputsMoved(context: context)
        let missingIDSet = ids.filter { lessonsByID[$0] == nil && !missingLessonIDs.contains($0) }
        guard !missingIDSet.isEmpty else { return }

        // PERFORMANCE: Fetch all lessons once and filter in memory
        // Core Data NSPredicate doesn't efficiently support IN queries with large UUID sets
        let request = CDFetchRequest(CDLesson.self)
        request.fetchLimit = 1000 // Safety limit for lesson library
        let allLessons = context.safeFetch(request)
        tableFetchCount += 1

        for lesson in allLessons {
            if let lessonID = lesson.id, missingIDSet.contains(lessonID) {
                lessonsByID[lessonID] = lesson
            }
        }
        missingLessonIDs.formUnion(missingIDSet.filter { lessonsByID[$0] == nil })
    }
}
