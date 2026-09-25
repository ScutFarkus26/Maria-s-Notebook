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

    // MARK: - Students

    /// Fetch all students, optionally filtering out test students and/or withdrawn students.
    /// `excludeWithdrawn` defaults to `true` — the active roster is the usual caller intent.
    /// Pass `excludeWithdrawn: false` when you need to resolve historical references (e.g. work,
    /// notes, or meetings that reference a student who has since been withdrawn).
    ///
    /// `sortBy` asks the store for that order (`[]` is store order). A sorted read
    /// goes straight to the store — not through the cache and without its safety
    /// limit — so it returns exactly the rows a whole-table `CDFetchRequest` would;
    /// callers that only need membership leave it nil and share the cache.
    func fetchAllStudents(
        excludeTest: Bool = false, excludeWithdrawn: Bool = true, sortBy: [NSSortDescriptor]? = nil
    ) -> [CDStudent] {
        let students: [CDStudent]
        if let sortBy {
            let request = CDFetchRequest(CDStudent.self)
            request.sortDescriptors = sortBy
            students = context.safeFetch(request)
        } else if let cached = studentsCache {
            students = cached
        } else {
            let request = CDFetchRequest(CDStudent.self)
            request.fetchLimit = 1000 // Safety limit for cache population
            students = context.safeFetch(request)
            studentsCache = students
        }

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

        return context.object(CDStudent.self, id: id)
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
    ///
    /// `sortBy` asks the store for that order (`[]` is store order) and `batchSize`
    /// is passed through as the request's `fetchBatchSize`. A sorted read goes
    /// straight to the store — not through the cache and without its safety limit
    /// — so it returns exactly the rows a whole-table `CDFetchRequest` would;
    /// callers that only need membership leave it nil and share the cache.
    func fetchAllLessons(sortBy: [NSSortDescriptor]? = nil, batchSize: Int = 0) -> [CDLesson] {
        if let sortBy {
            let request = CDFetchRequest(CDLesson.self)
            request.sortDescriptors = sortBy
            request.fetchBatchSize = batchSize
            return context.safeFetch(request)
        }
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

    /// The distinct non-empty lesson areas, sorted: exactly
    /// `Set(fetchAllLessons().map(\.area)).filter { !$0.isEmpty }.sorted()`,
    /// read as the one `area` column of the same (at most 2000) rows instead
    /// of whole lesson rows and their long text. A dictionary fetch reads the
    /// store, not the context, so while this context holds unsaved lesson
    /// changes — or once the lesson cache is loaded, which `fetchAllLessons`
    /// would answer from — it takes that managed-object read instead.
    func fetchLessonAreas() -> [String] {
        if lessonsCache != nil || hasUnsavedLessonChanges {
            return Set(fetchAllLessons().map(\.area)).filter { !$0.isEmpty }.sorted()
        }
        let request = NSFetchRequest<NSDictionary>(entityName: CDFetchRequest(CDLesson.self).entityName ?? "Lesson")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["area"]
        request.fetchLimit = 2000 // the rows fetchAllLessons() reads (its cache's safety limit)
        let rows: [NSDictionary]
        do {
            rows = try context.fetch(request)
        } catch {
            return Set(fetchAllLessons().map(\.area)).filter { !$0.isEmpty }.sorted()
        }
        return Set(rows.compactMap { $0["area"] as? String }).filter { !$0.isEmpty }.sorted()
    }

    private var hasUnsavedLessonChanges: Bool {
        guard context.hasChanges else { return false }
        return context.insertedObjects.contains { $0 is CDLesson }
            || context.updatedObjects.contains { $0 is CDLesson }
            || context.deletedObjects.contains { $0 is CDLesson }
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

        return context.object(CDLesson.self, id: id)
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
            format: "scheduledFor >= %@ AND scheduledFor < %@",
            startDate as NSDate, endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "scheduledFor", ascending: true)]
        return context.safeFetch(request)
    }

    // MARK: - WorkModels

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

    /// Invalidate just the lessons cache.
    func invalidateLessonsCache() {
        lessonsCache = nil
    }
}
