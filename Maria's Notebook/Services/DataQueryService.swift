import Foundation
import CoreData

/// Centralized service for common data queries with optional caching.
///
/// This consolidates common fetch patterns from across the codebase,
/// providing consistent error handling and optional caching for
/// frequently accessed data.
///
/// Usage:
/// ```swift
/// let service = DataQueryService(context: managedObjectContext)
/// let students = service.fetchAllStudents()
/// let lessons = service.fetchLessonsDictionary()
/// ```
@MainActor
final class DataQueryService {
    private let context: NSManagedObjectContext

    // MARK: - Caches

    private var studentsCache: [CDStudent]?
    private var lessonsCache: [UUID: CDLesson]?
    private var studentsByIDCache: [UUID: CDStudent]?

    // MARK: - Initialization

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // Deprecated ModelContext convenience init removed - no longer needed with Core Data.

    // MARK: - Students

    /// Fetch all students, optionally filtering out test students and/or withdrawn students.
    /// `excludeWithdrawn` defaults to `true` — the active roster is the usual caller intent.
    /// Pass `excludeWithdrawn: false` when you need to resolve historical references (e.g. work,
    /// notes, or meetings that reference a student who has since been withdrawn).
    func fetchAllStudents(excludeTest: Bool = false, excludeWithdrawn: Bool = true) -> [CDStudent] {
        if let cached = studentsCache {
            var result = cached
            if excludeWithdrawn { result = result.filterEnrolled() }
            return excludeTest ? TestStudentsFilter.filterVisible(result) : result
        }

        let request = CDFetchRequest(CDStudent.self)
        request.fetchLimit = 1000 // Safety limit for cache population
        let students = context.safeFetch(request)
        studentsCache = students

        var result = students
        if excludeWithdrawn { result = result.filterEnrolled() }
        return excludeTest ? TestStudentsFilter.filterVisible(result) : result
    }

    /// Fetch students by ID set.
    func fetchStudents(ids: Set<UUID>) -> [CDStudent] {
        guard !ids.isEmpty else { return [] }

        // Try to use cache if available
        if let cache = studentsByIDCache {
            return ids.compactMap { cache[$0] }
        }

        // PERFORMANCE: Fetch all students and filter with Set lookup (O(1) per check)
        // NSPredicate doesn't efficiently support IN with large local Set variables
        let request = CDFetchRequest(CDStudent.self)
        request.fetchLimit = 1000 // Safety limit
        let allStudents = context.safeFetch(request)
        // ids is already a Set, so .contains() is O(1)
        return allStudents.filter { id in
            guard let studentID = id.id else { return false }
            return ids.contains(studentID)
        }
    }

    /// Fetch a single student by ID.
    func fetchStudent(id: UUID) -> CDStudent? {
        if let cache = studentsByIDCache {
            return cache[id]
        }

        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetch(request).first
    }

    /// Get students as a dictionary keyed by ID.
    func fetchStudentsDictionary() -> [UUID: CDStudent] {
        if let cached = studentsByIDCache {
            return cached
        }

        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent crash on "Duplicate values for key"
        // Include withdrawn — this cache backs fetchStudent(id:) which must resolve historical references.
        let allStudents = fetchAllStudents(excludeWithdrawn: false)
        var seen = Set<UUID>()
        let students = allStudents.filter { s in
            guard let id = s.id else { return false }
            return seen.insert(id).inserted
        }
        let dict = Dictionary(
            students.compactMap { s -> (UUID, CDStudent)? in
                guard let id = s.id else { return nil }
                return (id, s)
            },
            uniquingKeysWith: { first, _ in first }
        )
        studentsByIDCache = dict
        return dict
    }

    // MARK: - Lessons

    /// Fetch all lessons.
    func fetchAllLessons() -> [CDLesson] {
        if let cached = lessonsCache {
            return Array(cached.values)
        }

        let request = CDFetchRequest(CDLesson.self)
        request.fetchLimit = 2000 // Safety limit for lesson library cache
        let lessons = context.safeFetch(request)
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        lessonsCache = Dictionary(
            lessons.compactMap { l -> (UUID, CDLesson)? in
                guard let id = l.id else { return nil }
                return (id, l)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return lessons
    }

    /// Fetch lessons by ID set.
    func fetchLessons(ids: Set<UUID>) -> [CDLesson] {
        guard !ids.isEmpty else { return [] }

        // Try to use cache if available
        if let cache = lessonsCache {
            return ids.compactMap { cache[$0] }
        }

        // PERFORMANCE: Fetch all lessons and filter with Set lookup (O(1) per check)
        // NSPredicate doesn't efficiently support IN with large local Set variables
        let allLessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        // ids is already a Set, so .contains() is O(1)
        return allLessons.filter { lesson in
            guard let lessonID = lesson.id else { return false }
            return ids.contains(lessonID)
        }
    }

    /// Fetch a single lesson by ID.
    func fetchLesson(id: UUID) -> CDLesson? {
        if let cache = lessonsCache {
            return cache[id]
        }

        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetch(request).first
    }

    /// Get lessons as a dictionary keyed by ID.
    func fetchLessonsDictionary() -> [UUID: CDLesson] {
        if let cached = lessonsCache {
            return cached
        }

        let lessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        let dict = Dictionary(
            lessons.compactMap { l -> (UUID, CDLesson)? in
                guard let id = l.id else { return nil }
                return (id, l)
            },
            uniquingKeysWith: { first, _ in first }
        )
        lessonsCache = dict
        return dict
    }

    // MARK: - LessonAssignments

    /// Fetch all presented lesson assignments (stateRaw == presented or presentedAt != nil).
    func fetchPresentedLessonAssignments() -> [CDLessonAssignment] {
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "stateRaw == %@", presentedRaw)
        var results = context.safeFetch(request)

        // Also fetch those with presentedAt but not in presented state
        let existingIDs = Set(results.compactMap(\.id))
        let notPresentedRequest = CDFetchRequest(CDLessonAssignment.self)
        notPresentedRequest.predicate = NSPredicate(format: "stateRaw != %@", presentedRaw)
        let notPresented = context.safeFetch(notPresentedRequest)
        let withPresentedAt = notPresented.filter { la in
            la.presentedAt != nil && !existingIDs.contains(la.id ?? UUID())
        }

        results.append(contentsOf: withPresentedAt)
        return results
    }

    /// Fetch lesson assignments for a specific student.
    /// CDNote: studentIDs is stored as JSON and is transient, so we fetch all and filter in memory.
    func fetchLessonAssignments(for studentID: UUID) -> [CDLessonAssignment] {
        let studentIDString = studentID.uuidString
        let allAssignments = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        return allAssignments.filter { $0.studentIDs.contains(studentIDString) }
    }

    /// Fetch lesson assignments in a date range.
    func fetchLessonAssignments(from startDate: Date, to endDate: Date) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "scheduledForDay >= %@ AND scheduledForDay < %@",
            startDate as NSDate, endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "scheduledForDay", ascending: true)]
        return context.safeFetch(request)
    }

    // MARK: - WorkModels

    /// Fetch work models by status.
    func fetchWorkModels(status: WorkStatus? = nil) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        if let status {
            request.predicate = NSPredicate(format: "statusRaw == %@", status.rawValue)
        }
        return context.safeFetch(request)
    }

    /// Fetch active or review work models.
    func fetchOpenWorkModels() -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "statusRaw == %@ OR statusRaw == %@",
            WorkStatus.active.rawValue, WorkStatus.review.rawValue
        )
        return context.safeFetch(request)
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
