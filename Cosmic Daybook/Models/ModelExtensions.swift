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

    /// The practice check-ins on work from this presentation, newest first.
    func fetchRelatedPracticeCheckIns(
        from context: NSManagedObjectContext,
        relatedWork workItems: [CDWorkModel]
    ) -> [CDWorkCheckIn] {
        CDWorkCheckIn.practice(onWorkIDs: Set(workItems.compactMap { $0.id?.uuidString }), in: context)
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

    /// The practice check-ins on this lesson's work, newest first.
    func fetchAllPracticeCheckIns(from context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        let workIDs = Set(fetchAllWork(from: context).compactMap { $0.id?.uuidString })
        return CDWorkCheckIn.practice(onWorkIDs: workIDs, in: context)
    }

}
