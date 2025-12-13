import Foundation
import SwiftData

@Model final class ScopedNote: Identifiable {
    // Scope enum is nested to avoid name collisions with any other NoteScope types
    enum Scope: Codable, Equatable {
        case all
        case student(UUID)
        case students([UUID])
    }

    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var body: String { didSet { updatedAt = Date() } }
    var scopeRaw: Data { didSet { updatedAt = Date() } }
    var legacyFingerprint: String?

    // Relationships (optional; at least one is expected to be set by the creator)
    var studentLesson: StudentLesson?
    var work: WorkModel?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        body: String = "",
        scope: Scope = .all,
        legacyFingerprint: String? = nil,
        studentLesson: StudentLesson? = nil,
        work: WorkModel? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.body = body
        self.legacyFingerprint = legacyFingerprint
        self.studentLesson = studentLesson
        self.work = work
        // Encode initial scope into scopeRaw; default to `.all` if encoding fails
        if let data = try? JSONEncoder().encode(scope) {
            self.scopeRaw = data
        } else {
            self.scopeRaw = (try? JSONEncoder().encode(Scope.all)) ?? Data()
        }
    }

    var scope: Scope {
        get {
            if let decoded = try? JSONDecoder().decode(Scope.self, from: scopeRaw) { return decoded }
            return .all
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                scopeRaw = data
            } else {
                // Fall back to `.all` if encoding fails
                scopeRaw = (try? JSONEncoder().encode(Scope.all)) ?? Data()
            }
        }
    }
}
