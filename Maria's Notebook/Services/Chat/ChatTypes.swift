import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date
    /// The rawValue of the AIModelOption that generated this response (assistant messages only).
    var modelID: String?
    /// Whether this message is an escalation prompt (special UI card, not a regular bubble).
    var isEscalationPrompt: Bool

    init(
        id: UUID = UUID(), role: ChatRole,
        content: String, timestamp: Date = Date(),
        modelID: String? = nil,
        isEscalationPrompt: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.modelID = modelID
        self.isEscalationPrompt = isEscalationPrompt
    }

    enum ChatRole: String, Codable {
        case user
        case assistant
    }
}

// MARK: - Chat Session

struct ChatSession: Codable {
    let id: UUID
    let startedAt: Date
    var messages: [ChatMessage]
    var classroomSnapshotText: String?
    var snapshotBuiltAt: Date?
    var mentionedStudentIDs: Set<UUID>

    /// CDStudent names available for dynamic suggested questions.
    var studentNames: [String]

    init(id: UUID = UUID()) {
        self.id = id
        self.startedAt = Date()
        self.messages = []
        self.classroomSnapshotText = nil
        self.snapshotBuiltAt = nil
        self.mentionedStudentIDs = []
        self.studentNames = []
    }

    /// Whether the classroom snapshot is stale and needs rebuilding.
    var isSnapshotStale: Bool {
        guard let built = snapshotBuiltAt else { return true }
        return Date().timeIntervalSince(built) > 300 // 5 minutes
    }

    // MARK: - Persistence

    private static let storageKey = "ChatSession.saved"

    /// Save session to UserDefaults.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Load a previously saved session from UserDefaults. Returns nil if none exists or is older than 24 hours.
    static func loadSaved() -> ChatSession? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let session = try? JSONDecoder().decode(ChatSession.self, from: data) else {
            return nil
        }
        // Discard sessions older than 24 hours
        if Date().timeIntervalSince(session.startedAt) > 86400 {
            clearSaved()
            return nil
        }
        return session
    }

    /// Clear the saved session.
    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
