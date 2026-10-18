import CoreData

/// What Ask AI's notebook tools work with while one answer is written: the
/// classroom the chat is answering in, and the records they cite.
/// `ChatService` makes one for each answer and hands it to the model client,
/// which gives it to the tools it builds for that answer.
///
/// The tools used to open the guide's own notebook whatever the window
/// showed, so Ask AI in Sample Class answered with her real children's
/// notes. The fix (2026-09-29) kept the classroom in one process-wide value,
/// so two Mac chat windows answering at once could read each other's
/// classroom, and one window's answer could clear or show the other's
/// sources (bug hunt 2026-10-11 #53). The model framework calls the tools on
/// tasks of its own, so the context can't travel as a task-local; it travels
/// inside the tools instead.
@MainActor
final class ChatToolContext {
    /// The chat's classroom; `nil` for the guide's own notebook.
    private let store: NSManagedObjectContext?

    /// The records the tools looked up for this answer, shown as its Sources.
    let sources = EvidenceSourceCollector()

    /// What the tools saved for this answer, in order. "Record a meeting with
    /// Maya S" could save the meeting and then fail to answer (too long, a
    /// guardrail); chat put the question back to be sent again, filing a
    /// second meeting, or let Private Cloud, which has no tools, answer it
    /// over (bug hunt 2026-10-17 #9). After a write, neither happens.
    private(set) var writes: [ChatWrite] = []

    func recordWrite(_ write: ChatWrite) {
        writes.append(write)
    }

    /// What chat says when the answer failed after a write ("The meeting was
    /// recorded, but the answer couldn't be finished."), or nil when the
    /// tools saved nothing.
    var unfinishedAnswerMessage: String? {
        ChatWrite.unfinishedAnswerMessage(for: writes)
    }

    init(_ context: NSManagedObjectContext? = nil) {
        store = context
    }

    /// The chat's classroom, else the guide's own notebook.
    var context: NSManagedObjectContext {
        store ?? AppBootstrapping.getSharedCoreDataStack().viewContext
    }

    /// Whether that is the guide's own notebook: the search index covers
    /// only hers.
    var readsGuidesNotebook: Bool {
        context === AppBootstrapping.getSharedCoreDataStack().viewContext
    }
}

/// A change one of Ask AI's notebook tools saved.
nonisolated enum ChatWrite: CaseIterable, Sendable {
    case meeting
    case followUpAdded
    case followUpResolved

    /// "the meeting was recorded", "2 meetings were recorded".
    func clause(count: Int) -> String {
        switch self {
        case .meeting:
            count == 1 ? "the meeting was recorded" : "\(count) meetings were recorded"
        case .followUpAdded:
            count == 1 ? "the follow-up was added" : "\(count) follow-ups were added"
        case .followUpResolved:
            count == 1 ? "the follow-up was marked done" : "\(count) follow-ups were marked done"
        }
    }

    /// One sentence naming everything `writes` saved, or nil for none.
    static func unfinishedAnswerMessage(for writes: [ChatWrite]) -> String? {
        let clauses = allCases.compactMap { kind -> String? in
            let count = writes.count { $0 == kind }
            return count > 0 ? kind.clause(count: count) : nil
        }
        guard let last = clauses.last else { return nil }
        let joined = clauses.count == 1
            ? last
            : clauses.dropLast().joined(separator: ", ") + " and " + last
        return joined.prefix(1).uppercased() + joined.dropFirst() + ", but the answer couldn't be finished."
    }
}

/// The records an answer's notebook tools looked up, one entry per record.
actor EvidenceSourceCollector {
    private var sourcesByID: [String: EvidenceReference] = [:]

    func record(_ reference: EvidenceReference) {
        sourcesByID[reference.id] = reference
    }

    func record(contentsOf references: [EvidenceReference]) {
        for reference in references {
            sourcesByID[reference.id] = reference
        }
    }

    func snapshot() -> [EvidenceReference] {
        sourcesByID.values.sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }

    func consume() -> [EvidenceReference] {
        let snapshot = snapshot()
        sourcesByID.removeAll()
        return snapshot
    }
}
