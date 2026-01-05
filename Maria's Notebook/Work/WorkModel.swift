import Foundation
import SwiftData
import SwiftUI

@Model final class WorkModel: Identifiable {
    enum WorkType: String, CaseIterable, Codable {
        case research = "Research"
        case followUp = "Follow Up"
        case practice = "Practice"
    }

    var id: UUID = UUID()
    var title: String = ""
    // Persisted raw value for the enum to keep storage simple and stable
    private var workTypeRaw: String = "Research"
    var studentLessonID: UUID? = nil
    var notes: String = ""
    var createdAt: Date = Date()
    var completedAt: Date? = nil
    @Relationship(deleteRule: .cascade, inverse: \WorkParticipantEntity.work) var participants: [WorkParticipantEntity]? = []
    @Relationship(deleteRule: .cascade, inverse: \WorkCheckIn.work) var checkIns: [WorkCheckIn]? = []
    // CloudKit compatibility: Relationship arrays must be optional
    @Relationship(deleteRule: .cascade, inverse: \Note.work) var noteItems: [Note]? = []
    @Relationship(deleteRule: .cascade, inverse: \ScopedNote.work) var scopedNotes: [ScopedNote]? = []
    @Relationship(deleteRule: .cascade, inverse: \WorkNote.work) var checkNotes: [WorkNote]? = []

    init(
        id: UUID = UUID(),
        title: String = "",
        workType: WorkType = .research,
        studentLessonID: UUID? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        participants: [WorkParticipantEntity] = []
    ) {
        self.id = id
        self.title = title
        self.workTypeRaw = workType.rawValue
        self.studentLessonID = studentLessonID
        self.notes = notes
        // Use Calendar.current instead of AppCalendar.shared to avoid MainActor isolation in init
        let cal = Calendar.current
        self.createdAt = cal.startOfDay(for: createdAt)
        self.completedAt = completedAt.map { cal.startOfDay(for: $0) }
        self.participants = participants
        self.noteItems = []
        self.scopedNotes = []
        for p in (self.participants ?? []) { p.work = self }
    }

    var workType: WorkType {
        get { WorkType(rawValue: workTypeRaw) ?? .research }
        set { workTypeRaw = newValue.rawValue }
    }

    // MARK: - Completion helpers
    var isCompleted: Bool { completedAt != nil }

    /// A work item is considered open if any participant has not completed their work.
    /// If there are no participants, treat it as open so it appears in triage lists.
    var isOpen: Bool {
        // If no participants have been assigned, consider it open
        if (participants ?? []).isEmpty { return true }
        // Otherwise open if any participant has not completed
        return (participants ?? []).contains { $0.completedAt == nil }
    }

    func participant(for studentID: UUID) -> WorkParticipantEntity? {
        let studentIDString = studentID.uuidString
        return (participants ?? []).first { $0.studentID == studentIDString }
    }

    func isStudentCompleted(_ studentID: UUID) -> Bool {
        return participant(for: studentID)?.completedAt != nil
    }

    // TODO: Consider moving this "action" logic to a Service or ViewModel to avoid Model-layer database insertion.
    func markStudent(_ studentID: UUID, completedAt date: Date?) {
        // Use Calendar.current to avoid MainActor constraints
        let cal = Calendar.current
        let normalized = date.map { cal.startOfDay(for: $0) }
        let studentIDString = studentID.uuidString
        if participants == nil { participants = [] }
        if let idx = participants?.firstIndex(where: { $0.studentID == studentIDString }) {
            participants?[idx].completedAt = normalized
        } else {
            participants = (participants ?? []) + [WorkParticipantEntity(studentID: studentID, completedAt: normalized, work: self)]
        }
    }
}
