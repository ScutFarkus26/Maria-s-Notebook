import Foundation

public enum NoteCategory: String, Codable, CaseIterable {
    case academic
    case behavioral
    case social
    case emotional
    case health
    case attendance
    case general
}

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

    nonisolated init(from decoder: Decoder) throws {
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

    nonisolated func encode(to encoder: Encoder) throws {
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
