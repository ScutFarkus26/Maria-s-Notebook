import Foundation
import CoreData
import OSLog

nonisolated private let logger = Logger.database

// MARK: - NSManagedObjectContext Extensions

nonisolated extension NSManagedObjectContext {
    /// Resolves a CDWorkModel by primary ID.
    func resolveWorkModel(from workID: UUID) -> CDWorkModel? {
        object(CDWorkModel.self, id: workID)
    }
}

// MARK: - CDWorkModel Extensions

nonisolated extension CDWorkModel {
    /// Fetches the presentation that spawned this work item
    func fetchPresentation(from context: NSManagedObjectContext) -> CDLessonAssignment? {
        guard let presentationID,
              let uuid = UUID(uuidString: presentationID) else { return nil }

        return context.object(CDLessonAssignment.self, id: uuid)
    }

    /// Fetches the lesson associated with this work item
    func fetchLesson(from context: NSManagedObjectContext) -> CDLesson? {
        guard !lessonID.isEmpty,
              let uuid = UUID(uuidString: lessonID) else { return nil }

        return context.object(CDLesson.self, id: uuid)
    }

    /// Fetches the student assigned to this work item
    func fetchStudent(from context: NSManagedObjectContext) -> CDStudent? {
        guard !studentID.isEmpty,
              let uuid = UUID(uuidString: studentID) else { return nil }

        return context.object(CDStudent.self, id: uuid)
    }

}

// MARK: - Presentation (CDLessonAssignment) Extensions

nonisolated extension CDLessonAssignment {
    /// Fetches all work items spawned from this presentation
    func fetchRelatedWork(from context: NSManagedObjectContext) -> [CDWorkModel] {
        let presentationIDString = id?.uuidString ?? ""
        guard !presentationIDString.isEmpty else { return [] }

        let request = CDFetchRequest(CDWorkModel.self)
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

        // Narrow in the store. The *assignment's* ID list is a Transformable and
        // isn't queryable, but the students' own `id` is a plain UUID attribute —
        // so the already-parsed UUIDs go straight into the predicate instead of
        // faulting in every student row and filtering in Swift.
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", uuids)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)]

        do {
            return try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch students: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetches practice sessions related to work from this presentation
    func fetchRelatedPracticeSessions(from context: NSManagedObjectContext) -> [CDPracticeSession] {
        fetchRelatedPracticeSessions(from: context, relatedWork: fetchRelatedWork(from: context))
    }

    /// Same, for a caller that already holds `fetchRelatedWork(from:)`'s result.
    func fetchRelatedPracticeSessions(
        from context: NSManagedObjectContext,
        relatedWork workItems: [CDWorkModel]
    ) -> [CDPracticeSession] {
        let workIDs = Set(workItems.compactMap { $0.id?.uuidString })
        guard !workIDs.isEmpty else { return [] }

        // Fetch all practice sessions and filter in memory
        // Core Data predicates don't support complex array operations on Transformable
        let request = CDFetchRequest(CDPracticeSession.self)
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
        let completed = work.filter { $0.status.isClosed }.count
        return (completed, work.count)
    }
}

// MARK: - CDLesson Extensions

nonisolated extension CDLesson {
    /// Fetches all presentations (lesson assignments) of this lesson
    func fetchAllPresentations(from context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let lessonIDString = id?.uuidString ?? ""
        guard !lessonIDString.isEmpty else { return [] }

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonAssignment.scheduledFor, ascending: false)]

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

        let request = CDFetchRequest(CDWorkModel.self)
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
        let request = CDFetchRequest(CDPracticeSession.self)
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

}

// MARK: - Supporting Types
