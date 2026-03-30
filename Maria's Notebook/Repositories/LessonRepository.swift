//
//  LessonRepository.swift
//  Maria's Notebook
//
//  Repository for Lesson entity CRUD operations.
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

    /// Fetch a Lesson by ID
    func fetchLesson(id: UUID) -> CDLesson? {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch multiple Lessons with optional filtering and sorting
    func fetchLessons(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [
            NSSortDescriptor(key: "subject", ascending: true),
            NSSortDescriptor(key: "group", ascending: true),
            NSSortDescriptor(key: "sortIndex", ascending: true)
        ]
    ) -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        return context.safeFetch(request)
    }

    /// Fetch lessons by subject
    func fetchLessons(bySubject subject: String) -> [CDLesson] {
        fetchLessons(predicate: NSPredicate(format: "subject == %@", subject))
    }

    /// Fetch lessons by subject and group
    func fetchLessons(bySubject subject: String, group: String) -> [CDLesson] {
        fetchLessons(predicate: NSPredicate(format: "subject == %@ AND group == %@", subject, group))
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

    /// Create a new Lesson
    @discardableResult
    func createLesson(
        name: String,
        subject: String,
        group: String = "",
        subheading: String = "",
        writeUp: String = "",
        orderInGroup: Int = 0,
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
        lesson.subject = subject
        lesson.group = group
        lesson.subheading = subheading
        lesson.writeUp = writeUp
        lesson.orderInGroup = Int64(orderInGroup)
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
        subject: String? = nil,
        group: String? = nil,
        subheading: String? = nil,
        writeUp: String? = nil,
        orderInGroup: Int? = nil,
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
        if let subject { lesson.subject = subject }
        if let group { lesson.group = group }
        if let subheading { lesson.subheading = subheading }
        if let writeUp { lesson.writeUp = writeUp }
        if let orderInGroup { lesson.orderInGroup = Int64(orderInGroup) }
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

    /// Delete a Lesson by ID
    func deleteLesson(id: UUID) throws {
        guard let lesson = fetchLesson(id: id) else { return }
        context.delete(lesson)
        try context.save()
    }
}
