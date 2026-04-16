import Foundation
import CoreData

// MARK: - Today Cache Manager

/// Manager for caching students, lessons, and work data in TodayViewModel.
/// Provides efficient lookup dictionaries and lazy computation of derived values.
@MainActor
final class TodayCacheManager {

    // MARK: - Cached Data

    private(set) var studentsByID: [UUID: CDStudent] = [:]
    private(set) var lessonsByID: [UUID: CDLesson] = [:]
    private(set) var workByID: [UUID: CDWorkModel] = [:]

    // MARK: - Duplicate Names Cache

    private var cachedDuplicateFirstNames: Set<String>?

    /// Returns first names that appear more than once among cached students.
    var duplicateFirstNames: Set<String> {
        if let cached = cachedDuplicateFirstNames {
            return cached
        }
        let firsts = studentsByID.values.map { $0.firstName.trimmed().lowercased() }
        var counts: [String: Int] = [:]
        for f in firsts { counts[f, default: 0] += 1 }
        let duplicates = Set(counts.filter { $0.value > 1 }.map(\.key))
        cachedDuplicateFirstNames = duplicates
        return duplicates
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Update Methods

    /// Updates the students cache with new values.
    func updateStudents(_ students: [UUID: CDStudent]) {
        studentsByID = students
        cachedDuplicateFirstNames = nil
    }

    /// Merges additional students into the cache.
    func mergeStudents(_ students: [CDStudent]) {
        for student in students {
            if let studentID = student.id {
                studentsByID[studentID] = student
            }
        }
        cachedDuplicateFirstNames = nil
    }

    /// Updates the lessons cache with new values.
    func updateLessons(_ lessons: [UUID: CDLesson]) {
        lessonsByID = lessons
    }

    /// Merges additional lessons into the cache.
    func mergeLessons(_ lessons: [CDLesson]) {
        for lesson in lessons {
            if let lessonID = lesson.id {
                lessonsByID[lessonID] = lesson
            }
        }
    }

    /// Updates the work cache with new values.
    func updateWork(_ work: [UUID: CDWorkModel]) {
        workByID = work
    }

    // MARK: - Display Name Helpers

    /// Returns the display name for a student ID, using first name + last initial if duplicate.
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

    /// Returns the lesson name for a lesson ID.
    func lessonName(for lessonID: UUID) -> String {
        lessonsByID[lessonID]?.name ?? "Lesson"
    }

    // MARK: - Loading Methods

    /// Loads students if not already cached.
    func loadStudentsIfNeeded(ids: Set<UUID>, context: NSManagedObjectContext) {
        guard !ids.isEmpty else { return }

        let missingIDs = ids.filter { studentsByID[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        // PERFORMANCE: Fetch all students once and filter in memory
        // Core Data NSPredicate doesn't efficiently support IN queries with large UUID sets
        let request = CDFetchRequest(CDStudent.self)
        request.fetchLimit = 500 // Safety limit for student roster
        let allStudents = context.safeFetch(request).filterEnrolled()

        // OPTIMIZATION: Use Set for O(1) lookups instead of repeated array searches
        let missingIDSet = Set(missingIDs)
        let filtered = allStudents.filter { student in
            guard let studentID = student.id else { return false }
            return missingIDSet.contains(studentID)
        }
        let visibleStudents = TestStudentsFilter.filterVisible(filtered)

        for student in visibleStudents {
            if let studentID = student.id {
                studentsByID[studentID] = student
            }
        }
        cachedDuplicateFirstNames = nil
    }

    /// Loads lessons if not already cached.
    func loadLessonsIfNeeded(ids: Set<UUID>, context: NSManagedObjectContext) {
        guard !ids.isEmpty else { return }

        let missingIDs = ids.filter { lessonsByID[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        // PERFORMANCE: Fetch all lessons once and filter in memory
        // Core Data NSPredicate doesn't efficiently support IN queries with large UUID sets
        let request = CDFetchRequest(CDLesson.self)
        request.fetchLimit = 1000 // Safety limit for lesson library
        let allLessons = context.safeFetch(request)

        // OPTIMIZATION: Use Set for O(1) lookups instead of repeated array searches
        let missingIDSet = Set(missingIDs)
        let filtered = allLessons.filter { lesson in
            guard let lessonID = lesson.id else { return false }
            return missingIDSet.contains(lessonID)
        }

        for lesson in filtered {
            if let lessonID = lesson.id {
                lessonsByID[lessonID] = lesson
            }
        }
    }

    // MARK: - Clear Cache

    /// Clears all cached data.
    func clearAll() {
        studentsByID = [:]
        lessonsByID = [:]
        workByID = [:]
        cachedDuplicateFirstNames = nil
    }
}
