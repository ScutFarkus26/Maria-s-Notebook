import Foundation
import CoreData
import OSLog

private let logger = Logger.database

// MARK: - NSManagedObjectContext Extensions

extension NSManagedObjectContext {
    /// Resolves a CDWorkModel by ID with automatic fallback to legacy contract ID
    func resolveWorkModel(from workID: UUID) -> CDWorkModel? {
        // Try primary ID first
        let primaryRequest = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        primaryRequest.predicate = NSPredicate(format: "id == %@", workID as CVarArg)
        if let model = safeFetchFirst(primaryRequest) {
            return model
        }

        // Fallback to legacy contract ID
        let legacyRequest = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        legacyRequest.predicate = NSPredicate(format: "legacyContractID == %@", workID as CVarArg)
        return safeFetchFirst(legacyRequest)
    }
}

// MARK: - WorkModel Extensions

extension CDWorkModel {
    /// Fetches the presentation that spawned this work item
    func fetchPresentation(from context: NSManagedObjectContext) -> CDLessonAssignment? {
        guard let presentationID,
              let uuid = UUID(uuidString: presentationID) else { return nil }

        let request = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        do {
            return try context.fetch(request).first
        } catch {
            logger.warning("Failed to fetch presentation: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches the lesson associated with this work item
    func fetchLesson(from context: NSManagedObjectContext) -> CDLesson? {
        guard !lessonID.isEmpty,
              let uuid = UUID(uuidString: lessonID) else { return nil }

        let request = NSFetchRequest<CDLesson>(entityName: "Lesson")
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        do {
            return try context.fetch(request).first
        } catch {
            logger.warning("Failed to fetch lesson: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches the student assigned to this work item
    func fetchStudent(from context: NSManagedObjectContext) -> CDStudent? {
        guard !studentID.isEmpty,
              let uuid = UUID(uuidString: studentID) else { return nil }

        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        do {
            return try context.fetch(request).first
        } catch {
            logger.warning("Failed to fetch student: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches all practice sessions that include this work item
    func fetchPracticeSessions(from context: NSManagedObjectContext) -> [CDPracticeSession] {
        let workIDString = id?.uuidString ?? ""
        guard !workIDString.isEmpty else { return [] }

        // Fetch all practice sessions and filter in memory
        // Core Data predicates don't support contains() on Transformable arrays
        let request = NSFetchRequest<CDPracticeSession>(entityName: "PracticeSession")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDPracticeSession.date, ascending: false)]

        let allSessions: [CDPracticeSession]
        do {
            allSessions = try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch practice sessions: \(error.localizedDescription)")
            return []
        }
        return allSessions.filter { session in
            session.workItemIDsArray.contains(workIDString)
        }
    }
}

// MARK: - Presentation (LessonAssignment) Extensions

extension CDLessonAssignment {
    /// Fetches all work items spawned from this presentation
    func fetchRelatedWork(from context: NSManagedObjectContext) -> [CDWorkModel] {
        let presentationIDString = id?.uuidString ?? ""
        guard !presentationIDString.isEmpty else { return [] }

        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        request.predicate = NSPredicate(format: "presentationID == %@", presentationIDString)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: true)]

        do {
            return try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch related work: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetches all students assigned to this presentation
    func fetchStudents(from context: NSManagedObjectContext) -> [CDStudent] {
        let studentUUIDStrings = studentIDs
        guard !studentUUIDStrings.isEmpty else { return [] }

        // Convert string IDs to UUIDs
        let uuids = studentUUIDStrings.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [] }

        // Fetch all students and filter in-memory
        // Core Data predicates don't support id.uuidString keypaths on Transformable arrays
        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)]

        let allStudents: [CDStudent]
        do {
            allStudents = try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch students: \(error.localizedDescription)")
            return []
        }
        return allStudents.filter { student in
            guard let studentID = student.id else { return false }
            return studentUUIDStrings.contains(studentID.uuidString)
        }
    }

    /// Fetches practice sessions related to work from this presentation
    func fetchRelatedPracticeSessions(from context: NSManagedObjectContext) -> [CDPracticeSession] {
        let workItems = fetchRelatedWork(from: context)
        let workIDs = Set(workItems.compactMap { $0.id?.uuidString })
        guard !workIDs.isEmpty else { return [] }

        // Fetch all practice sessions and filter in memory
        // Core Data predicates don't support complex array operations on Transformable
        let request = NSFetchRequest<CDPracticeSession>(entityName: "PracticeSession")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDPracticeSession.date, ascending: false)]

        let allSessions: [CDPracticeSession]
        do {
            allSessions = try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch practice sessions: \(error.localizedDescription)")
            return []
        }
        return allSessions.filter { session in
            session.workItemIDsArray.contains(where: { workIDs.contains($0) })
        }
    }

    /// Returns work completion statistics for this presentation
    func workCompletionStats(from context: NSManagedObjectContext) -> (completed: Int, total: Int) {
        let work = fetchRelatedWork(from: context)
        let completed = work.filter { $0.status == .complete }.count
        return (completed, work.count)
    }
}

// MARK: - Lesson Extensions

extension CDLesson {
    /// Fetches all presentations (lesson assignments) of this lesson
    func fetchAllPresentations(from context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let lessonIDString = id?.uuidString ?? ""
        guard !lessonIDString.isEmpty else { return [] }

        let request = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonAssignment.scheduledForDay, ascending: false)]

        do {
            return try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch presentations: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetches all work items related to this lesson
    func fetchAllWork(from context: NSManagedObjectContext) -> [CDWorkModel] {
        let lessonIDString = id?.uuidString ?? ""
        guard !lessonIDString.isEmpty else { return [] }

        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)]

        do {
            return try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch work items: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetches all practice sessions involving this lesson's work
    func fetchAllPracticeSessions(from context: NSManagedObjectContext) -> [CDPracticeSession] {
        let workItems = fetchAllWork(from: context)
        let workIDs = Set(workItems.compactMap { $0.id?.uuidString })
        guard !workIDs.isEmpty else { return [] }

        // Fetch all practice sessions and filter in memory
        // Core Data predicates don't support complex array operations on Transformable
        let request = NSFetchRequest<CDPracticeSession>(entityName: "PracticeSession")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDPracticeSession.date, ascending: false)]

        let allSessions: [CDPracticeSession]
        do {
            allSessions = try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch practice sessions: \(error.localizedDescription)")
            return []
        }
        return allSessions.filter { session in
            session.workItemIDsArray.contains(where: { workIDs.contains($0) })
        }
    }

    /// Returns statistics about this lesson's usage
    func getLessonStats(from context: NSManagedObjectContext) -> LessonStats {
        let presentations = fetchAllPresentations(from: context)
        let work = fetchAllWork(from: context)
        let practiceSessions = fetchAllPracticeSessions(from: context)

        let presentedCount = presentations.filter { $0.state == .presented }.count
        let completedWork = work.filter { $0.status == .complete }.count

        return LessonStats(
            totalPresentations: presentations.count,
            presentedCount: presentedCount,
            scheduledCount: presentations.filter { $0.state == .scheduled }.count,
            totalWorkItems: work.count,
            completedWorkItems: completedWork,
            activeWorkItems: work.filter { $0.status == .active }.count,
            totalPracticeSessions: practiceSessions.count,
            lastPresentedDate: presentations.compactMap(\.presentedAt).max()
        )
    }
}

// MARK: - PracticeSession Extensions

extension CDPracticeSession {
    /// Fetches all students who participated in this session
    func fetchStudents(from context: NSManagedObjectContext) -> [CDStudent] {
        let studentIDStrings = studentIDsArray
        guard !studentIDStrings.isEmpty else { return [] }

        // Convert string IDs to UUIDs for querying
        let uuids = studentIDStrings.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [] }

        // Fetch students by UUIDs
        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)]

        let allStudents: [CDStudent]
        do {
            allStudents = try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch students: \(error.localizedDescription)")
            return []
        }
        return allStudents.filter { student in
            guard let studentID = student.id else { return false }
            return studentIDStrings.contains(studentID.uuidString)
        }
    }

    /// Fetches all work items practiced in this session
    func fetchWorkItems(from context: NSManagedObjectContext) -> [CDWorkModel] {
        let workIDStrings = workItemIDsArray
        guard !workIDStrings.isEmpty else { return [] }

        // Convert string IDs to UUIDs for querying
        let uuids = workIDStrings.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [] }

        // Fetch all work items and filter in memory
        // Core Data predicates don't support checking if UUID is in Transformable array
        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        let allWork: [CDWorkModel]
        do {
            allWork = try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch work items: \(error.localizedDescription)")
            return []
        }

        return allWork.filter { work in
            guard let workID = work.id else { return false }
            return workIDStrings.contains(workID.uuidString)
        }
    }

    /// Fetches the common lesson if all work items are for the same lesson
    func fetchCommonLesson(from context: NSManagedObjectContext) -> CDLesson? {
        let workItems = fetchWorkItems(from: context)
        guard !workItems.isEmpty else { return nil }

        let lessonIDs = Set(workItems.map(\.lessonID))
        guard lessonIDs.count == 1,
              let lessonID = lessonIDs.first,
              let uuid = UUID(uuidString: lessonID) else { return nil }

        let request = NSFetchRequest<CDLesson>(entityName: "Lesson")
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        do {
            return try context.fetch(request).first
        } catch {
            logger.warning("Failed to fetch common lesson: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Supporting Types

struct LessonStats {
    let totalPresentations: Int
    let presentedCount: Int
    let scheduledCount: Int
    let totalWorkItems: Int
    let completedWorkItems: Int
    let activeWorkItems: Int
    let totalPracticeSessions: Int
    let lastPresentedDate: Date?

    var workCompletionRate: Double {
        guard totalWorkItems > 0 else { return 0 }
        return Double(completedWorkItems) / Double(totalWorkItems)
    }
}
