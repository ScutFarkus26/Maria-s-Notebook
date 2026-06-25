//
//  StudentEntity.swift
//  Maria's Notebook
//
//  App Intents representation of a student. This is what lets Siri, Spotlight,
//  and Apple Intelligence refer to a student by name (e.g. "log an observation
//  about Maria"). It is a lightweight, Sendable value snapshot of `CDStudent`.
//

import AppIntents
import CoreData
import CoreSpotlight
import UniformTypeIdentifiers

/// A Siri/Spotlight-facing view of a student.
///
/// Conforms to `IndexedEntity` so instances can be indexed into Spotlight's
/// semantic index, which is what the modern Siri and Spotlight search read from.
struct StudentEntity: AppEntity, IndexedEntity {
    let id: UUID
    let firstName: String
    let lastName: String
    let nickname: String?

    /// Human-readable full name, falling back gracefully when a part is blank.
    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Student")
    }

    var displayRepresentation: DisplayRepresentation {
        if let nickname, !nickname.isEmpty {
            return DisplayRepresentation(
                title: "\(fullName)",
                subtitle: "\(nickname)",
                image: .init(systemName: "person.crop.circle")
            )
        }
        return DisplayRepresentation(
            title: "\(fullName)",
            image: .init(systemName: "person.crop.circle")
        )
    }

    /// Spotlight metadata. Enriched with name parts so searching any of them
    /// surfaces the student.
    var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .text)
        set.title = fullName
        set.displayName = fullName
        set.contentDescription = "Student"
        var keywords = [firstName, lastName]
        if let nickname, !nickname.isEmpty { keywords.append(nickname) }
        set.keywords = keywords.filter { !$0.isEmpty }
        return set
    }

    static let defaultQuery = StudentEntityQuery()
}

// MARK: - Conversion from Core Data

extension StudentEntity {
    /// Builds an entity snapshot from a managed student. Must be called on the
    /// main actor because it reads `CDStudent` properties off the view context.
    @MainActor
    init?(student: CDStudent) {
        guard let id = student.id else { return nil }
        self.init(
            id: id,
            firstName: student.firstName,
            lastName: student.lastName,
            nickname: student.nickname
        )
    }
}

// MARK: - Query

/// Resolves students for Siri/Shortcuts: by id, by typed/spoken name, and as
/// suggestions for App Shortcut phrases.
struct StudentEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [StudentEntity] {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", identifiers)
        return context.safeFetch(request).compactMap { StudentEntity(student: $0) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [StudentEntity] {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(
            format: "firstName CONTAINS[cd] %@ OR lastName CONTAINS[cd] %@ OR nickname CONTAINS[cd] %@",
            string, string, string
        )
        request.sortDescriptors = CDStudent.sortByName
        return context.safeFetch(request).compactMap { StudentEntity(student: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [StudentEntity] {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(
            format: "enrollmentStatusRaw == %@",
            CDStudent.EnrollmentStatus.enrolled.rawValue
        )
        request.sortDescriptors = CDStudent.sortByName
        return context.safeFetch(request).compactMap { StudentEntity(student: $0) }
    }
}
