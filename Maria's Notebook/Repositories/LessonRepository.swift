//
//  LessonRepository.swift
//  Maria's Notebook
//
//  Repository for Lesson entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import OSLog
import SwiftData

@MainActor
struct LessonRepository: SavingRepository {
    typealias Model = Lesson

    private static let logger = Logger.database

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a Lesson by ID
    func fetchLesson(id: UUID) -> Lesson? {
        var descriptor = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch multiple Lessons with optional filtering and sorting
    /// - Parameters:
    ///   - predicate: Optional predicate to filter lessons. If nil, fetches all.
    ///   - sortBy: Optional sort descriptors. Defaults to sorting by subject, group, sortIndex.
    /// - Returns: Array of Lesson entities matching the criteria
    func fetchLessons(
        predicate: Predicate<Lesson>? = nil,
        sortBy: [SortDescriptor<Lesson>] = [
            SortDescriptor(\.subject),
            SortDescriptor(\.group),
            SortDescriptor(\.sortIndex)
        ]
    ) -> [Lesson] {
        var descriptor = FetchDescriptor<Lesson>()
        if let predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    /// Fetch lessons by subject
    func fetchLessons(bySubject subject: String) -> [Lesson] {
        let predicate = #Predicate<Lesson> { $0.subject == subject }
        return fetchLessons(predicate: predicate)
    }

    /// Fetch lessons by subject and group
    func fetchLessons(bySubject subject: String, group: String) -> [Lesson] {
        let predicate = #Predicate<Lesson> { $0.subject == subject && $0.group == group }
        return fetchLessons(predicate: predicate)
    }

    /// Fetch all root story lessons (stories with no parent)
    func fetchRootStories() -> [Lesson] {
        let storyRaw = LessonFormat.story.rawValue
        let predicate = #Predicate<Lesson> {
            $0.lessonFormatRaw == storyRaw && $0.parentStoryID == nil
        }
        return fetchLessons(predicate: predicate)
    }

    /// Fetch child stories that branch off a given parent story
    func fetchChildStories(parentID: UUID) -> [Lesson] {
        let parentIDString = parentID.uuidString
        let predicate = #Predicate<Lesson> { $0.parentStoryID == parentIDString }
        return fetchLessons(predicate: predicate)
    }

    // MARK: - Create

    /// Create a new Lesson
    /// - Parameters:
    ///   - name: Lesson name
    ///   - subject: Subject area (e.g., Math, Language)
    ///   - group: Group/category within subject
    ///   - subheading: Short description
    ///   - writeUp: Detailed lesson content
    ///   - orderInGroup: Manual order within group
    ///   - sortIndex: Order within subject
    ///   - source: Lesson source (album or personal)
    ///   - personalKind: Kind when source is personal
    ///   - defaultWorkKind: Preferred work type for this lesson
    /// - Returns: The created Lesson entity
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
    ) -> Lesson {
        let lesson = Lesson(
            name: name,
            subject: subject,
            group: group,
            orderInGroup: orderInGroup,
            sortIndex: sortIndex,
            subheading: subheading,
            writeUp: writeUp,
            sourceRaw: source.rawValue,
            personalKindRaw: personalKind?.rawValue,
            defaultWorkKind: defaultWorkKind,
            materials: materials,
            purpose: purpose,
            ageRange: ageRange,
            teacherNotes: teacherNotes,
            lessonFormatRaw: lessonFormat.rawValue,
            parentStoryID: parentStoryID
        )
        context.insert(lesson)
        return lesson
    }

    // MARK: - Update

    // Update an existing Lesson's properties
    @discardableResult
    // swiftlint:disable:next cyclomatic_complexity
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
        if let orderInGroup { lesson.orderInGroup = orderInGroup }
        if let sortIndex { lesson.sortIndex = sortIndex }
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
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error, privacy: .public)")
            throw error
        }
    }
}
