//
//  SpotlightIndexer.swift
//  Maria's Notebook
//
//  Indexes students and lessons into Spotlight's semantic index so they appear
//  in phone search and can be referenced by the modern Siri / Apple Intelligence.
//  Indexing AppEntities (not raw CSSearchableItems) links each result back to its
//  Open intent, so tapping a result routes into the app.
//

import AppIntents
import CoreData
import CoreSpotlight
import OSLog

enum SpotlightIndexer {
    private static let logger = Logger.app(category: "Spotlight")

    /// Re-indexes students and lessons. Idempotent — safe on every launch and
    /// whenever the data changes.
    @MainActor
    static func reindexAll() async {
        await reindexStudents()
        await reindexLessons()
    }

    @MainActor
    static func reindexStudents() async {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(
            format: "enrollmentStatusRaw == %@",
            CDStudent.EnrollmentStatus.enrolled.rawValue
        )
        request.sortDescriptors = CDStudent.sortByName

        let entities = context.safeFetch(request).compactMap { StudentEntity(student: $0) }
        guard !entities.isEmpty else { return }
        do {
            try await CSSearchableIndex.default().indexAppEntities(entities)
            logger.info("Indexed \(entities.count) students into Spotlight.")
        } catch {
            logger.warning("Failed to index students into Spotlight: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func reindexLessons() async {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDLesson.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]

        let entities = context.safeFetch(request).compactMap { LessonEntity(lesson: $0) }
        guard !entities.isEmpty else { return }
        do {
            try await CSSearchableIndex.default().indexAppEntities(entities)
            logger.info("Indexed \(entities.count) lessons into Spotlight.")
        } catch {
            logger.warning("Failed to index lessons into Spotlight: \(error.localizedDescription)")
        }
    }
}
