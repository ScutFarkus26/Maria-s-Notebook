import Foundation
import SwiftData

/// Centralized service for common data queries with optional caching.
///
/// This consolidates common fetch patterns from across the codebase,
/// providing consistent error handling and optional caching for
/// frequently accessed data.
///
/// Usage:
/// ```swift
/// let service = DataQueryService(context: modelContext)
/// let students = service.fetchAllStudents()
/// let lessons = service.fetchLessonsDictionary()
/// ```
@MainActor
final class DataQueryService {
    private let context: ModelContext

    // MARK: - Caches

    private var studentsCache: [Student]?
    private var lessonsCache: [UUID: Lesson]?
    private var studentsByIDCache: [UUID: Student]?

    // MARK: - Initialization

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Students

    /// Fetch all students, optionally filtering out test students and/or withdrawn students.
    func fetchAllStudents(excludeTest: Bool = false, excludeWithdrawn: Bool = false) -> [Student] {
        if let cached = studentsCache {
            var result = cached
            if excludeWithdrawn { result = result.filter { $0.isEnrolled } }
            return excludeTest ? TestStudentsFilter.filterVisible(result) : result
        }

        var descriptor = FetchDescriptor<Student>()
        descriptor.fetchLimit = 1000 // Safety limit for cache population
        let students = context.safeFetch(descriptor)
        studentsCache = students

        var result = students
        if excludeWithdrawn { result = result.filter { $0.isEnrolled } }
        return excludeTest ? TestStudentsFilter.filterVisible(result) : result
    }

    /// Fetch students by ID set.
    func fetchStudents(ids: Set<UUID>) -> [Student] {
        guard !ids.isEmpty else { return [] }

        // Try to use cache if available
        if let cache = studentsByIDCache {
            return ids.compactMap { cache[$0] }
        }

        // PERFORMANCE: Fetch all students and filter with Set lookup (O(1) per check)
        // SwiftData #Predicate doesn't support capturing local Set variables
        var descriptor = FetchDescriptor<Student>()
        descriptor.fetchLimit = 1000 // Safety limit
        let allStudents = context.safeFetch(descriptor)
        // ids is already a Set, so .contains() is O(1)
        return allStudents.filter { ids.contains($0.id) }
    }

    /// Fetch a single student by ID.
    func fetchStudent(id: UUID) -> Student? {
        if let cache = studentsByIDCache {
            return cache[id]
        }

        var descriptor = FetchDescriptor<Student>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return context.safeFetch(descriptor).first
    }

    /// Get students as a dictionary keyed by ID.
    func fetchStudentsDictionary() -> [UUID: Student] {
        if let cached = studentsByIDCache {
            return cached
        }

        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent crash on "Duplicate values for key"
        let students = fetchAllStudents().uniqueByID
        let dict = students.toDictionary(by: \.id)
        studentsByIDCache = dict
        return dict
    }

    // MARK: - Lessons

    /// Fetch all lessons.
    func fetchAllLessons() -> [Lesson] {
        if let cached = lessonsCache {
            return Array(cached.values)
        }

        var descriptor = FetchDescriptor<Lesson>()
        descriptor.fetchLimit = 2000 // Safety limit for lesson library cache
        let lessons = context.safeFetch(descriptor)
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        lessonsCache = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return lessons
    }

    /// Fetch lessons by ID set.
    func fetchLessons(ids: Set<UUID>) -> [Lesson] {
        guard !ids.isEmpty else { return [] }

        // Try to use cache if available
        if let cache = lessonsCache {
            return ids.compactMap { cache[$0] }
        }

        // PERFORMANCE: Fetch all lessons and filter with Set lookup (O(1) per check)
        // SwiftData #Predicate doesn't support capturing local Set variables
        let allLessons = context.safeFetch(FetchDescriptor<Lesson>())
        // ids is already a Set, so .contains() is O(1)
        return allLessons.filter { ids.contains($0.id) }
    }

    /// Fetch a single lesson by ID.
    func fetchLesson(id: UUID) -> Lesson? {
        if let cache = lessonsCache {
            return cache[id]
        }

        var descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return context.safeFetch(descriptor).first
    }

    /// Get lessons as a dictionary keyed by ID.
    func fetchLessonsDictionary() -> [UUID: Lesson] {
        if let cached = lessonsCache {
            return cached
        }

        let lessons = context.safeFetch(FetchDescriptor<Lesson>())
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        let dict = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lessonsCache = dict
        return dict
    }

    // MARK: - LessonAssignments

    /// Fetch all presented lesson assignments (stateRaw == presented or presentedAt != nil).
    func fetchPresentedLessonAssignments() -> [LessonAssignment] {
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.stateRaw == presentedRaw }
        )
        var results = context.safeFetch(descriptor)

        // Also fetch those with presentedAt but not in presented state
        let existingIDs = Set(results.map { $0.id })
        let notPresentedDescriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.stateRaw != presentedRaw }
        )
        let notPresented = context.safeFetch(notPresentedDescriptor)
        let withPresentedAt = notPresented.filter { $0.presentedAt != nil && !existingIDs.contains($0.id) }

        results.append(contentsOf: withPresentedAt)
        return results
    }

    /// Fetch lesson assignments for a specific student.
    /// Note: studentIDs is stored as JSON and is transient, so we fetch all and filter in memory.
    func fetchLessonAssignments(for studentID: UUID) -> [LessonAssignment] {
        let studentIDString = studentID.uuidString
        let allAssignments = context.safeFetch(FetchDescriptor<LessonAssignment>())
        return allAssignments.filter { $0.studentIDs.contains(studentIDString) }
    }

    /// Fetch lesson assignments in a date range.
    func fetchLessonAssignments(from startDate: Date, to endDate: Date) -> [LessonAssignment] {
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { la in
                la.scheduledForDay >= startDate && la.scheduledForDay < endDate
            },
            sortBy: [SortDescriptor(\.scheduledForDay)]
        )
        return context.safeFetch(descriptor)
    }

    // MARK: - WorkModels

    /// Fetch work models by status.
    func fetchWorkModels(status: WorkStatus? = nil) -> [WorkModel] {
        if let status = status {
            let statusRaw = status.rawValue
            let descriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate { $0.statusRaw == statusRaw }
            )
            return context.safeFetch(descriptor)
        } else {
            return context.safeFetch(FetchDescriptor<WorkModel>())
        }
    }

    /// Fetch active or review work models.
    func fetchOpenWorkModels() -> [WorkModel] {
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.statusRaw == activeRaw || work.statusRaw == reviewRaw
            }
        )
        return context.safeFetch(descriptor)
    }

    // MARK: - Cache Management

    /// Invalidate all caches.
    func invalidateAllCaches() {
        studentsCache = nil
        lessonsCache = nil
        studentsByIDCache = nil
    }

    /// Invalidate just the students cache.
    func invalidateStudentsCache() {
        studentsCache = nil
        studentsByIDCache = nil
    }

    /// Invalidate just the lessons cache.
    func invalidateLessonsCache() {
        lessonsCache = nil
    }
}
