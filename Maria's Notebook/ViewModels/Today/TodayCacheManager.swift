import Foundation
import SwiftData

// MARK: - Today Cache Manager

/// Manager for caching students, lessons, and work data in TodayViewModel.
/// Provides efficient lookup dictionaries and lazy computation of derived values.
@MainActor
final class TodayCacheManager {

    // MARK: - Cached Data

    private(set) var studentsByID: [UUID: Student] = [:]
    private(set) var lessonsByID: [UUID: Lesson] = [:]
    private(set) var workByID: [UUID: WorkModel] = [:]

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
        let duplicates = Set(counts.filter { $0.value > 1 }.map { $0.key })
        cachedDuplicateFirstNames = duplicates
        return duplicates
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Update Methods

    /// Updates the students cache with new values.
    func updateStudents(_ students: [UUID: Student]) {
        studentsByID = students
        cachedDuplicateFirstNames = nil
    }

    /// Merges additional students into the cache.
    func mergeStudents(_ students: [Student]) {
        for student in students {
            studentsByID[student.id] = student
        }
        cachedDuplicateFirstNames = nil
    }

    /// Updates the lessons cache with new values.
    func updateLessons(_ lessons: [UUID: Lesson]) {
        lessonsByID = lessons
    }

    /// Merges additional lessons into the cache.
    func mergeLessons(_ lessons: [Lesson]) {
        for lesson in lessons {
            lessonsByID[lesson.id] = lesson
        }
    }

    /// Updates the work cache with new values.
    func updateWork(_ work: [UUID: WorkModel]) {
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
    func loadStudentsIfNeeded(ids: Set<UUID>, context: ModelContext) {
        guard !ids.isEmpty else { return }

        let missingIDs = ids.filter { studentsByID[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let allStudents = context.safeFetch(FetchDescriptor<Student>())
        let filtered = allStudents.filter { missingIDs.contains($0.id) }
        let visibleStudents = TestStudentsFilter.filterVisible(filtered)
        for student in visibleStudents {
            studentsByID[student.id] = student
        }
        cachedDuplicateFirstNames = nil
    }

    /// Loads lessons if not already cached.
    func loadLessonsIfNeeded(ids: Set<UUID>, context: ModelContext) {
        guard !ids.isEmpty else { return }

        let missingIDs = ids.filter { lessonsByID[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let allLessons = context.safeFetch(FetchDescriptor<Lesson>())
        let filtered = allLessons.filter { missingIDs.contains($0.id) }
        for lesson in filtered {
            lessonsByID[lesson.id] = lesson
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
