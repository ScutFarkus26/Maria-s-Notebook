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
    /// The name Siri shows for this child, when the app names children
    /// differently from `fullName` (`SiriHost.displayNames`).
    var displayName: String?
    /// Her first name as another child in the class spells it, where the two
    /// sound just the same (Sara for Sarah): set by the query from the class
    /// (`soundAlikeNames(in:)`).
    var soundAlikeNames: [String] = []

    /// Human-readable full name, falling back gracefully when a part is blank.
    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Student")
    }

    /// The other names a child answers to, so "Mark Maya here" finds Maya
    /// Stone. Two children sharing a first name both carry it, and Siri asks
    /// which one was meant; two whose first names only sound the same carry
    /// each other's spelling too (`soundAlikeNames`).
    var spokenNames: [String] {
        var names = [firstName]
        if let nickname, !nickname.isEmpty { names.append(nickname) }
        if let initial = lastName.first, !firstName.isEmpty { names.append("\(firstName) \(initial)") }
        names += soundAlikeNames
        return names.filter { !$0.isEmpty }
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource? = nickname.flatMap { $0.isEmpty ? nil : "\($0)" }
        return DisplayRepresentation(
            title: "\(displayName ?? fullName)",
            subtitle: subtitle,
            image: .init(systemName: "person.crop.circle"),
            synonyms: spokenNames.map { LocalizedStringResource(stringLiteral: $0) }
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

    /// Each child's sound-alike spellings among `classmates`: where two
    /// current children's first names sound just the same but are spelled
    /// differently (Sara Klein and Sarah Adler, `StudentNameMatcher
    /// .soundFolded`), each gets the other's spelling. An App Shortcut phrase
    /// can resolve a name from the synonyms alone, never asking
    /// `entities(matching:)`, so "Sarah" found only Sarah though the
    /// recognizer's spelling is a guess; with both spellings on both, Siri
    /// finds two and asks which (bug hunt 2026-10-20 review). A name spelled
    /// the same needs nothing: both children already carry it.
    static func soundAlikeNames(in classmates: [StudentEntity]) -> [UUID: [String]] {
        func spelling(_ entity: StudentEntity) -> String {
            entity.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let named = classmates.filter { !StudentNameMatcher.normalized(spelling($0)).isEmpty }
        let groups = Dictionary(grouping: named) { StudentNameMatcher.soundFolded(spelling($0)) }
        var result: [UUID: [String]] = [:]
        for group in groups.values where group.count > 1 {
            for entity in group {
                var seen: Set<String> = [StudentNameMatcher.normalized(spelling(entity))]
                let others = group.map(spelling).filter { seen.insert(StudentNameMatcher.normalized($0)).inserted }
                if !others.isEmpty { result[entity.id] = others }
            }
        }
        return result
    }
}

// MARK: - Query

/// Resolves students for Siri/Shortcuts: by id, by typed/spoken name, and as
/// suggestions for App Shortcut phrases.
struct StudentEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [StudentEntity] {
        let context = try await SiriAttendance.openStack().viewContext
        return Self.entities(for: identifiers, in: context)
    }

    /// The children with these ids, named as the app names them: Siri shows
    /// this name when it confirms a child it resolved by id (a shortcut, a
    /// follow-up), on a locked phone too. The names are worked out against
    /// the whole class, which "Etty G" needs the other Etty for.
    @MainActor
    static func entities(for identifiers: [UUID], in context: NSManagedObjectContext) -> [StudentEntity] {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", identifiers)
        let students = context.safeFetch(request)
        let roster = SiriHost.roster(in: context)
        let names = SiriHost.displayNames(for: Array(Set(roster).union(students)))
        let alike = StudentEntity.soundAlikeNames(in: roster.compactMap { StudentEntity(student: $0) })
        return students.compactMap { student in
            guard var entity = StudentEntity(student: student) else { return nil }
            entity.displayName = names[student.objectID]
            entity.soundAlikeNames = alike[entity.id] ?? []
            return entity
        }
    }

    /// The class first, then former students (`SiriHost.formerStudents`),
    /// exact names before sound-alikes (`StudentNameMatcher.matches(for:
    /// current:former:)`): "Open Leah" still finds a child who has left,
    /// "Mark Leah here" never picks her over a current Leah, and a current
    /// Lea is never marked for her.
    @MainActor
    func entities(matching string: String) async throws -> [StudentEntity] {
        let context = try await SiriAttendance.openStack().viewContext
        let current = Self.entities(SiriHost.roster(in: context))
        let currentIDs = Set(current.map(\.id))
        var former: [StudentEntity] = []
        let found = StudentNameMatcher.matches(for: string, current: current.map(\.matcherCandidate)) {
            former = SiriHost.formerStudents(in: context)
                .compactMap { StudentEntity(student: $0) }
                .filter { !currentIDs.contains($0.id) }
            return former.map(\.matcherCandidate)
        }
        let ids = Set(found.map(\.id))
        return (current + former).filter { ids.contains($0.id) }
    }

    /// The names Siri learns for App Shortcut phrases: the current class.
    @MainActor
    func suggestedEntities() async throws -> [StudentEntity] {
        let context = try await SiriAttendance.openStack().viewContext
        return Self.entities(SiriHost.roster(in: context))
    }

    /// The class as entities, each titled as the app names it and carrying
    /// her sound-alike spellings.
    @MainActor
    static func entities(_ students: [CDStudent]) -> [StudentEntity] {
        let names = SiriHost.displayNames(for: students)
        let entities = students.compactMap { student -> StudentEntity? in
            guard var entity = StudentEntity(student: student) else { return nil }
            entity.displayName = names[student.objectID]
            return entity
        }
        let alike = StudentEntity.soundAlikeNames(in: entities)
        return entities.map { entity in
            var entity = entity
            entity.soundAlikeNames = alike[entity.id] ?? []
            return entity
        }
    }
}
