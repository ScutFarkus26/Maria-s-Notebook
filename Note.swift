import Foundation
import SwiftData

enum NoteScope: Codable, Equatable {
    case all
    case student(UUID)
    case students([UUID])

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case ids
    }

    enum ScopeType: String, Codable {
        case all
        case student
        case students
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ScopeType.self, forKey: .type)
        switch type {
        case .all:
            self = .all
        case .student:
            let id = try container.decode(UUID.self, forKey: .id)
            self = .student(id)
        case .students:
            let ids = try container.decode([UUID].self, forKey: .ids)
            self = .students(ids)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try container.encode(ScopeType.all, forKey: .type)
            try container.encodeNil(forKey: .id)
            try container.encodeNil(forKey: .ids)
        case .student(let id):
            try container.encode(ScopeType.student, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeNil(forKey: .ids)
        case .students(let ids):
            try container.encode(ScopeType.students, forKey: .type)
            try container.encodeNil(forKey: .id)
            try container.encode(ids, forKey: .ids)
        }
    }

    var isAll: Bool {
        if case .all = self {
            return true
        }
        return false
    }

    func applies(to studentID: UUID) -> Bool {
        switch self {
        case .all:
            return true
        case .student(let id):
            return id == studentID
        case .students(let ids):
            return ids.contains(studentID)
        }
    }
}

@Model
final class Note: Identifiable {
    // Identity & timestamps
    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    // Content
    var body: String
    var isPinned: Bool

    // Persisted scope storage (JSON-encoded) kept small; no external storage needed
    private var scopeBlob: Data?

    // Relationships (optional). Inverse to Lesson.notes only; WorkModel inverse added later.
    @Relationship(inverse: \Lesson.notes) var lesson: Lesson?
    @Relationship var work: WorkModel?

    // Computed, Codable scope
    @MainActor var scope: NoteScope {
        get { decodeScope() ?? .all }
        set { scopeBlob = try? JSONEncoder().encode(newValue) }
    }

    // Initializer with defaults
    @MainActor init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        body: String,
        scope: NoteScope = .all,
        isPinned: Bool = false,
        lesson: Lesson? = nil,
        work: WorkModel? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.body = body
        self.isPinned = isPinned
        self.lesson = lesson
        self.work = work
        self.scopeBlob = try? JSONEncoder().encode(scope)
    }

    // MARK: - Private helpers
    @MainActor private func decodeScope() -> NoteScope? {
        guard let data = scopeBlob else { return nil }
        return try? JSONDecoder().decode(NoteScope.self, from: data)
    }
}

// TODO: Migrate any legacy string notes on Lesson/Work into Note objects when ready.

