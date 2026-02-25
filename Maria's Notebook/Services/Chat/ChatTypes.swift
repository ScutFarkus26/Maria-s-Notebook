import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    enum ChatRole: String {
        case user
        case assistant
    }
}

// MARK: - Chat Session

struct ChatSession {
    let id: UUID
    let startedAt: Date
    var messages: [ChatMessage]
    var classroomSnapshotText: String?
    var snapshotBuiltAt: Date?
    var mentionedStudentIDs: Set<UUID>

    init(id: UUID = UUID()) {
        self.id = id
        self.startedAt = Date()
        self.messages = []
        self.classroomSnapshotText = nil
        self.snapshotBuiltAt = nil
        self.mentionedStudentIDs = []
    }

    /// Whether the classroom snapshot is stale and needs rebuilding.
    var isSnapshotStale: Bool {
        guard let built = snapshotBuiltAt else { return true }
        return Date().timeIntervalSince(built) > 300 // 5 minutes
    }
}
