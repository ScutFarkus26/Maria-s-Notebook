//
//  StudentEntity.swift
//  Cosmic Daybook
//
//  App Intents representation of a student. This is what lets Siri, Spotlight,
//  and Apple Intelligence refer to a student by name (e.g. "log an observation
//  about Maria"). It is a lightweight, Sendable value snapshot of `CDStudent`.
//
//  Shared with Daybook Assistant, which compiles this file by path: it reaches
//  the store only through `SiriHost`, which each app defines for itself.
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

    /// The other names a child answers to, so "Mark Maya here" finds Maya
    /// Stone. Two children sharing a first name both carry it, and Siri asks
    /// which one was meant.
    private var spokenNames: [LocalizedStringResource] {
        var names = [firstName]
        if let nickname, !nickname.isEmpty { names.append(nickname) }
        if let initial = lastName.first, !firstName.isEmpty { names.append("\(firstName) \(initial)") }
        return names.filter { !$0.isEmpty }.map { LocalizedStringResource(stringLiteral: $0) }
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource? = nickname.flatMap { $0.isEmpty ? nil : "\($0)" }
        return DisplayRepresentation(
            title: "\(fullName)",
            subtitle: subtitle,
            image: .init(systemName: "person.crop.circle"),
            synonyms: spokenNames
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

    var matcherCandidate: StudentNameMatcher.Candidate {
        StudentNameMatcher.Candidate(id: id, firstName: firstName, lastName: lastName, nickname: nickname)
    }
}

// MARK: - Query

/// Resolves students for Siri/Shortcuts: by id, by typed/spoken name, and as
/// suggestions for App Shortcut phrases.
struct StudentEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [StudentEntity] {
        let context = try SiriHost.stack().viewContext
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", identifiers)
        return context.safeFetch(request).compactMap { StudentEntity(student: $0) }
    }

    /// The class first; only when no current child matches does it look at
    /// former students, so "Open Leah" still finds a child who has left while
    /// "Mark Leah here" never picks her over a current Leah.
    @MainActor
    func entities(matching string: String) async throws -> [StudentEntity] {
        let context = try SiriHost.stack().viewContext
        let current = SiriHost.roster(in: context).compactMap { StudentEntity(student: $0) }
        let found = Self.matches(for: string, in: current)
        if !found.isEmpty { return found }

        let request = CDFetchRequest(CDStudent.self)
        request.sortDescriptors = CDStudent.sortByName
        let everyone = context.safeFetch(request).compactMap { StudentEntity(student: $0) }
        return Self.matches(for: string, in: everyone)
    }

    /// The names Siri learns for App Shortcut phrases: the current class.
    @MainActor
    func suggestedEntities() async throws -> [StudentEntity] {
        let context = try SiriHost.stack().viewContext
        return SiriHost.roster(in: context).compactMap { StudentEntity(student: $0) }
    }

    private static func matches(for string: String, in students: [StudentEntity]) -> [StudentEntity] {
        let ids = Set(StudentNameMatcher.matches(for: string, in: students.map(\.matcherCandidate)).map(\.id))
        return students.filter { ids.contains($0.id) }
    }
}
