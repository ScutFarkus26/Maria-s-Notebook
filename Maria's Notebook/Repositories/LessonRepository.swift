//
//  LessonRepository.swift
//  Maria's Notebook
//
//  Repository for CDLesson entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct LessonRepository: SavingRepository {
    typealias Model = CDLesson

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDLesson by ID
    func fetchLesson(id: UUID) -> CDLesson? { fetch(id: id) }

    /// Fetch multiple Lessons with optional filtering and sorting
    func fetchLessons(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [
            NSSortDescriptor(key: "area", ascending: true),
            NSSortDescriptor(key: "sequence", ascending: true),
            NSSortDescriptor(key: "sortIndex", ascending: true)
        ]
    ) -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    /// Fetch lessons by area
    func fetchLessons(byArea area: String) -> [CDLesson] {
        fetchLessons(predicate: NSPredicate(format: "area == %@", area))
    }

    /// Fetch lessons by area and sequence
    func fetchLessons(byArea area: String, sequence: String) -> [CDLesson] {
        fetchLessons(predicate: NSPredicate(format: "area == %@ AND sequence == %@", area, sequence))
    }

    /// Fetch child stories that branch off a given parent story
    func fetchChildStories(parentID: UUID) -> [CDLesson] {
        fetchLessons(predicate: NSPredicate(format: "parentStoryID == %@", parentID.uuidString))
    }

    // MARK: - Create

    /// Create a new CDLesson
    @discardableResult
    func createLesson(
        name: String,
        area: String,
        sequence: String = "",
        section: String = "",
        writeUp: String = "",
        orderInSequence: Int = 0,
        sortIndex: Int = 0,
        source: LessonSource = .album,
        personalKind: PersonalLessonKind? = nil,
        defaultWorkKind: WorkKind? = nil,
        materials: String = "",
        purpose: String = "",
        ageRange: String = "",
        teacherNotes: String = "",
        lessonFormat: LessonFormat = .standard,
        parentStoryID: String? = nil
    ) -> CDLesson {
        let lesson = CDLesson(context: context)
        lesson.name = name
        lesson.area = area
        lesson.sequence = sequence
        lesson.section = section
        lesson.writeUp = writeUp
        lesson.orderInSequence = Int64(orderInSequence)
        lesson.sortIndex = Int64(sortIndex)
        lesson.source = source
        lesson.personalKind = personalKind
        lesson.defaultWorkKind = defaultWorkKind
        lesson.materials = materials
        lesson.purpose = purpose
        lesson.ageRange = ageRange
        lesson.teacherNotes = teacherNotes
        lesson.lessonFormat = lessonFormat
        lesson.parentStoryID = parentStoryID
        return lesson
    }

    // MARK: - Delete

    /// Delete a CDLesson by ID
    func deleteLesson(id: UUID) throws {
        guard let lesson = fetchLesson(id: id) else { return }
        context.delete(lesson)
        try context.save()
    }
}
