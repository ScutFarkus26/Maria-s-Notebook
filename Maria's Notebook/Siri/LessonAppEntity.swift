//
//  LessonAppEntity.swift
//  Maria's Notebook
//
//  App Intents representation of a lesson. Lets Siri / Spotlight / Apple
//  Intelligence refer to a lesson by name (e.g. "mark the bead frame as
//  presented to Eli") and surfaces lessons in phone search.
//

import AppIntents
import CoreData
import CoreSpotlight
import UniformTypeIdentifiers

/// A Siri/Spotlight-facing view of a lesson. Lightweight, Sendable snapshot of `CDLesson`.
struct LessonEntity: AppEntity, IndexedEntity {
    let id: UUID
    let name: String
    let area: String
    let sequence: String

    /// Short context line: area · sequence (omitting blanks).
    var contextLine: String {
        [area, sequence].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Lesson")
    }

    var displayRepresentation: DisplayRepresentation {
        let context = contextLine
        if context.isEmpty {
            return DisplayRepresentation(title: "\(name)", image: .init(systemName: "book"))
        }
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(context)",
            image: .init(systemName: "book")
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .text)
        set.title = name
        set.displayName = name
        set.contentDescription = contextLine.isEmpty ? "Lesson" : contextLine
        set.keywords = [name, area, sequence].filter { !$0.isEmpty }
        return set
    }

    static let defaultQuery = LessonEntityQuery()
}

// MARK: - Conversion from Core Data

extension LessonEntity {
    @MainActor
    init?(lesson: CDLesson) {
        guard let id = lesson.id, !lesson.name.isEmpty else { return nil }
        self.init(id: id, name: lesson.name, area: lesson.area, sequence: lesson.sequence)
    }
}

// MARK: - Query

struct LessonEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [LessonEntity] {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", identifiers)
        return context.safeFetch(request).compactMap { LessonEntity(lesson: $0) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [LessonEntity] {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(
            format: "name CONTAINS[cd] %@ OR area CONTAINS[cd] %@ OR sequence CONTAINS[cd] %@",
            string, string, string
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]
        request.fetchLimit = 50
        return context.safeFetch(request).compactMap { LessonEntity(lesson: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [LessonEntity] {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDLesson.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]
        request.fetchLimit = 100
        return context.safeFetch(request).compactMap { LessonEntity(lesson: $0) }
    }
}
