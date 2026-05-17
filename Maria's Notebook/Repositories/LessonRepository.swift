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
    func fetchLesson(id: UUID) -> CDLesson? {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

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

    /// Fetch all root story lessons (stories with no parent)
    func fetchRootStories() -> [CDLesson] {
        let storyRaw = LessonFormat.story.rawValue
        return fetchLessons(predicate: NSPredicate(format: "lessonFormatRaw == %@ AND parentStoryID == nil", storyRaw))
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

    // MARK: - Update

    @discardableResult
    func updateLesson(
        id: UUID,
        name: String? = nil,
        area: String? = nil,
        sequence: String? = nil,
        section: String? = nil,
        writeUp: String? = nil,
        orderInSequence: Int? = nil,
        sortIndex: Int? = nil,
        defaultWorkKind: WorkKind? = nil,
        materials: String? = nil,
        purpose: String? = nil,
        ageRange: String? = nil,
        teacherNotes: String? = nil,
        prerequisiteLessonIDs: String? = nil,
        relatedLessonIDs: String? = nil,
        lessonFormat: LessonFormat? = nil,
        parentStoryID: String?? = nil
    ) -> Bool {
        guard let lesson = fetchLesson(id: id) else { return false }

        if let name { lesson.name = name }
        if let area { lesson.area = area }
        if let sequence { lesson.sequence = sequence }
        if let section { lesson.section = section }
        if let writeUp { lesson.writeUp = writeUp }
        if let orderInSequence { lesson.orderInSequence = Int64(orderInSequence) }
        if let sortIndex { lesson.sortIndex = Int64(sortIndex) }
        if let defaultWorkKind { lesson.defaultWorkKind = defaultWorkKind }
        if let materials { lesson.materials = materials }
        if let purpose { lesson.purpose = purpose }
        if let ageRange { lesson.ageRange = ageRange }
        if let teacherNotes { lesson.teacherNotes = teacherNotes }
        if let prerequisiteLessonIDs { lesson.prerequisiteLessonIDs = prerequisiteLessonIDs }
        if let relatedLessonIDs { lesson.relatedLessonIDs = relatedLessonIDs }
        if let lessonFormat { lesson.lessonFormat = lessonFormat }
        if let parentStoryID { lesson.parentStoryID = parentStoryID }

        return true
    }

    // MARK: - Delete

    /// Delete a CDLesson by ID
    func deleteLesson(id: UUID) throws {
        guard let lesson = fetchLesson(id: id) else { return }
        context.delete(lesson)
        try context.save()
    }
}
