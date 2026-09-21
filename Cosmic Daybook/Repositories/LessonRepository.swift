//
//  LessonRepository.swift
//  Cosmic Daybook
//
//  Repository for CDLesson entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

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

    // MARK: - Uniqueness

    /// A lesson name is unique within its sub-area (area + sequence). Names
    /// compare trimmed, case- and diacritic-insensitively — the same folding
    /// `find_lessons` and `create_lesson` use — so "Rectangle" and "rectangle "
    /// are one lesson. Parsha lessons are exempt: "Middle Girls" is filed
    /// fresh every week under a different `parshaKey`.
    enum CreationError: LocalizedError, Equatable {
        /// A lesson with this name already sits in the same sub-area.
        case duplicateName(existingID: UUID?, name: String, area: String, sequence: String)

        var errorDescription: String? {
            switch self {
            case let .duplicateName(_, name, area, sequence):
                let filing = sequence.trimmed().isEmpty ? area.trimmed() : "\(area.trimmed()) › \(sequence.trimmed())"
                return "\"\(name)\" is already in \(filing)."
            }
        }
    }

    /// The identity a lesson name has within the curriculum: its area,
    /// sub-area and name, each folded the way the Lessons screens compare them.
    nonisolated static func nameKey(name: String, area: String, sequence: String) -> String {
        [area, sequence, name].map { $0.folded() }.joined(separator: "|")
    }

    nonisolated static func nameKey(for lesson: CDLesson) -> String {
        nameKey(name: lesson.name, area: lesson.area, sequence: lesson.sequence)
    }

    /// Whether a lesson takes part in the name-uniqueness rule. Parsha lessons
    /// are keyed by week, not name, so they are left out on both sides.
    nonisolated static func participatesInNameUniqueness(_ lesson: CDLesson) -> Bool {
        participatesInNameUniqueness(parshaKey: lesson.parshaKey)
    }

    /// The same rule on the raw column, for callers that read `parshaKey`
    /// without materialising the lesson.
    nonisolated static func participatesInNameUniqueness(parshaKey: String?) -> Bool {
        (parshaKey ?? "").trimmed().isEmpty
    }

    /// The lesson already filed under `name` in this sub-area, if any.
    /// `excluding` lets a rename check skip the lesson being renamed.
    func existingLesson(
        named name: String, area: String, sequence: String, excluding: CDLesson? = nil
    ) -> CDLesson? {
        let key = Self.nameKey(name: name, area: area, sequence: sequence)
        let request = CDFetchRequest(CDLesson.self)
        request.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true)]
        return context.safeFetch(request).first { lesson in
            lesson !== excluding
                && !lesson.isDeleted
                && Self.participatesInNameUniqueness(lesson)
                && Self.nameKey(for: lesson) == key
        }
    }

    // MARK: - Create

    /// Create a new CDLesson.
    ///
    /// Refuses a name already used in the same sub-area (`CreationError.duplicateName`)
    /// so a sub-area entered twice no longer doubles every child's year plan.
    /// Pass `parshaKey` for a parsha lesson, which is exempt from that rule.
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
        parentStoryID: String? = nil,
        parshaKey: String? = nil
    ) throws -> CDLesson {
        let isParsha = !(parshaKey ?? "").trimmed().isEmpty
        if !isParsha, let existing = existingLesson(named: name, area: area, sequence: sequence) {
            throw CreationError.duplicateName(
                existingID: existing.id, name: name.trimmed(), area: area, sequence: sequence
            )
        }
        let lesson = CDLesson(context: context)
        lesson.parshaKey = parshaKey
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
