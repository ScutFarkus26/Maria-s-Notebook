import Foundation
import SwiftData

@Model final class WorkModel: Identifiable {
    enum WorkType: String, CaseIterable, Codable {
        case research = "Research"
        case followUp = "Follow Up"
        case practice = "Practice"
    }

    var id: UUID
    var studentIDs: [UUID]
    // Persisted raw value for the enum to keep storage simple and stable
    private var workTypeRaw: String
    var studentLessonID: UUID?
    var notes: String
    var createdAt: Date
    var completedAt: Date?
    var participants: [WorkParticipant]

    init(
        id: UUID = UUID(),
        studentIDs: [UUID] = [],
        workType: WorkType = .research,
        studentLessonID: UUID? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        participants: [WorkParticipant] = []
    ) {
        self.id = id
        self.studentIDs = studentIDs
        self.workTypeRaw = workType.rawValue
        self.studentLessonID = studentLessonID
        self.notes = notes
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.participants = participants
    }

    var workType: WorkType {
        get { WorkType(rawValue: workTypeRaw) ?? .research }
        set { workTypeRaw = newValue.rawValue }
    }

    // MARK: - Completion helpers
    var isCompleted: Bool { completedAt != nil }

    func participant(for studentID: UUID) -> WorkParticipant? {
        return participants.first { $0.studentID == studentID }
    }

    func isStudentCompleted(_ studentID: UUID) -> Bool {
        return participant(for: studentID)?.completedAt != nil
    }

    func markStudent(_ studentID: UUID, completedAt date: Date?) {
        if let idx = participants.firstIndex(where: { $0.studentID == studentID }) {
            participants[idx].completedAt = date
        } else {
            participants.append(WorkParticipant(studentID: studentID, completedAt: date))
        }
    }

    func ensureParticipantsFromStudentIDs() {
        // Ensure participants mirror studentIDs, preserving any existing completion dates
        let currentIDs = Set(participants.map { $0.studentID })
        let targetIDs = Set(studentIDs)
        // Add missing
        for id in targetIDs.subtracting(currentIDs) {
            participants.append(WorkParticipant(studentID: id))
        }
        // Remove extras (students removed from work)
        participants.removeAll { !targetIDs.contains($0.studentID) }
    }
}
