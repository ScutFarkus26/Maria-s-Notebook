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

    /// The hidden test students' names, normalized (Settings' list, or none
    /// while they're shown); tests pass their own.
    private let hiddenNames: () -> Set<String>
    /// The names the cached students were read under.
    private var cachedHiddenNames: Set<String>?

    init(hiddenNames: @escaping () -> Set<String> = { TestStudentsFilter.normalizedHiddenNames() }) {
        self.hiddenNames = hiddenNames
    }

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
    /// Student-table and lesson reads made so far (for tests pinning
    /// the miss caching).
    private(set) var tableFetchCount = 0

    nonisolated static let missInputEntities: Set<String> = ["Student", "Lesson"]

    /// Forgets the roster snapshot, the lesson misses and the cached students
    /// and lessons when a student or lesson changed since they were read. The
    /// cached students go too: a child who left (or was hidden) stayed on Today
    /// until the screen was rebuilt, since a cached id was never looked up again.
    /// A change to the hidden test students' list drops the students as well
    /// (bug hunt 2026-11-03 #55).
    private func dropMissesIfInputsMoved(context: NSManagedObjectContext) {
        let names = hiddenNames()
        if names != cachedHiddenNames {
            cachedHiddenNames = names
            studentsByID.removeAll()
        }
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
            studentsByID.removeAll()
            lessonsByID.removeAll()
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

    /// Whether `student` is shown: not on the hidden test students' list.
    private func isVisible(_ student: CDStudent, hidden: Set<String>) -> Bool {
        hidden.isEmpty || !hidden.contains(student.fullName.normalizedForComparison())
    }

    /// Enrolled, visible students among `ids`, for the meetings' and recent
    /// notes' names. Hidden test students used to be included, so their
    /// meetings and notes showed on Today (bug hunt 2026-11-03 #55).
    func enrolledStudents(ids: Set<UUID>, context: NSManagedObjectContext) -> [UUID: CDStudent] {
        guard !ids.isEmpty else { return [:] }
        let rows = rosterRows(context: context)
        let hidden = hiddenNames()
        var byID: [UUID: CDStudent] = [:]
        for student in rows.filterEnrolled() where isVisible(student, hidden: hidden) {
            guard let id = student.id, ids.contains(id) else { continue }
            byID[id] = student
        }
        return byID
    }

    /// The hidden test students' ids, enrolled or not: their meetings and the
    /// notes about only them stay off Today (`TodayHiddenStudents`).
    func hiddenStudentIDs(context: NSManagedObjectContext) -> Set<UUID> {
        let rows = rosterRows(context: context)
        let hidden = hiddenNames()
        guard !hidden.isEmpty else { return [] }
        return Set(rows.filter { !isVisible($0, hidden: hidden) }.compactMap(\.id))
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
        dropMissesIfInputsMoved(context: context)

        let missingIDSet = ids.filter { studentsByID[$0] == nil }
        guard !missingIDSet.isEmpty else { return }

        let hidden = hiddenNames()
        let visibleStudents = rosterRows(context: context).filterEnrolled().filter { student in
            guard let studentID = student.id else { return false }
            return missingIDSet.contains(studentID) && isVisible(student, hidden: hidden)
        }

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
        dropMissesIfInputsMoved(context: context)

        guard ids.contains(where: { lessonsByID[$0] == nil }) else { return }
        let missingIDSet = ids.filter { lessonsByID[$0] == nil && !missingLessonIDs.contains($0) }
        guard !missingIDSet.isEmpty else { return }

        // Only the lessons asked for, however large the library. A whole-table
        // read capped at 1,000 rows left every lesson past the cap reading
        // "Lesson" (bug hunt 2026-10-11 #71, as 10-10 #72 elsewhere).
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(missingIDSet))
        let fetched = context.safeFetch(request)
        tableFetchCount += 1

        for lesson in fetched {
            if let lessonID = lesson.id, missingIDSet.contains(lessonID) {
                lessonsByID[lessonID] = lesson
            }
        }
        missingLessonIDs.formUnion(missingIDSet.filter { lessonsByID[$0] == nil })
    }
}
