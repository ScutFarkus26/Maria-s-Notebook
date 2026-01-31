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

    /// Fetch all students, optionally filtering out test students.
    func fetchAllStudents(excludeTest: Bool = false) -> [Student] {
        if let cached = studentsCache {
            return excludeTest ? TestStudentsFilter.filterVisible(cached) : cached
        }

        let students = context.safeFetch(FetchDescriptor<Student>())
        studentsCache = students

        return excludeTest ? TestStudentsFilter.filterVisible(students) : students
    }

    /// Fetch students by ID set.
    func fetchStudents(ids: Set<UUID>) -> [Student] {
        guard !ids.isEmpty else { return [] }

        // Try to use cache if available
        if let cache = studentsByIDCache {
            return ids.compactMap { cache[$0] }
        }

        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let allStudents = context.safeFetch(FetchDescriptor<Student>())
        return allStudents.filter { ids.contains($0.id) }
    }

    /// Fetch a single student by ID.
    func fetchStudent(id: UUID) -> Student? {
        if let cache = studentsByIDCache {
            return cache[id]
        }

        let descriptor = FetchDescriptor<Student>(
            predicate: #Predicate { $0.id == id }
        )
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

        let lessons = context.safeFetch(FetchDescriptor<Lesson>())
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

        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let allLessons = context.safeFetch(FetchDescriptor<Lesson>())
        return allLessons.filter { ids.contains($0.id) }
    }

    /// Fetch a single lesson by ID.
    func fetchLesson(id: UUID) -> Lesson? {
        if let cache = lessonsCache {
            return cache[id]
        }

        let descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == id }
        )
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

    // MARK: - StudentLessons

    /// Fetch all presented student lessons (isPresented or givenAt != nil).
    func fetchPresentedStudentLessons() -> [StudentLesson] {
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.isPresented == true }
        )
        var results = context.safeFetch(descriptor)

        // Also fetch those with givenAt but not isPresented
        let existingIDs = Set(results.map { $0.id })
        let notPresentedDescriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.isPresented == false }
        )
        let notPresented = context.safeFetch(notPresentedDescriptor)
        let withGivenAt = notPresented.filter { $0.givenAt != nil && !existingIDs.contains($0.id) }

        results.append(contentsOf: withGivenAt)
        return results
    }

    /// Fetch student lessons for a specific student.
    /// Note: studentIDs is stored as JSON and is transient, so we fetch all and filter in memory.
    func fetchStudentLessons(for studentID: UUID) -> [StudentLesson] {
        let studentIDString = studentID.uuidString
        let allLessons = context.safeFetch(FetchDescriptor<StudentLesson>())
        return allLessons.filter { $0.studentIDs.contains(studentIDString) }
    }

    /// Fetch student lessons in a date range.
    func fetchStudentLessons(from startDate: Date, to endDate: Date) -> [StudentLesson] {
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { sl in
                sl.scheduledForDay >= startDate && sl.scheduledForDay < endDate
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
