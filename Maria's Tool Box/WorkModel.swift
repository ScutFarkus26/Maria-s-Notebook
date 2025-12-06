import Foundation
import SwiftData
import SwiftUI

@Model final class WorkModel: Identifiable {
    enum WorkType: String, CaseIterable, Codable {
        case research = "Research"
        case followUp = "Follow Up"
        case practice = "Practice"
    }

    var id: UUID
    var title: String
    var studentIDs: [UUID]
    // Persisted raw value for the enum to keep storage simple and stable
    private var workTypeRaw: String
    var studentLessonID: UUID?
    var notes: String
    var createdAt: Date
    var completedAt: Date?
    @Relationship(inverse: \WorkParticipantEntity.work) var participants: [WorkParticipantEntity] = []
    @Relationship(inverse: \WorkCheckIn.work) var checkIns: [WorkCheckIn] = []

    init(
        id: UUID = UUID(),
        title: String = "",
        studentIDs: [UUID] = [],
        workType: WorkType = .research,
        studentLessonID: UUID? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        participants: [WorkParticipantEntity] = []
    ) {
        self.id = id
        self.title = title
        self.studentIDs = studentIDs
        self.workTypeRaw = workType.rawValue
        self.studentLessonID = studentLessonID
        self.notes = notes
        let cal = Calendar.current
        self.createdAt = cal.startOfDay(for: createdAt)
        self.completedAt = completedAt.map { cal.startOfDay(for: $0) }
        self.participants = participants
        for p in self.participants { p.work = self }
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
        if participants.isEmpty { return true }
        // Otherwise open if any participant has not completed
        return participants.contains { $0.completedAt == nil }
    }

    func participant(for studentID: UUID) -> WorkParticipantEntity? {
        return participants.first { $0.studentID == studentID }
    }

    func isStudentCompleted(_ studentID: UUID) -> Bool {
        return participant(for: studentID)?.completedAt != nil
    }

    func markStudent(_ studentID: UUID, completedAt date: Date?) {
        let cal = Calendar.current
        let normalized = date.map { cal.startOfDay(for: $0) }
        if let idx = participants.firstIndex(where: { $0.studentID == studentID }) {
            participants[idx].completedAt = normalized
        } else {
            participants.append(WorkParticipantEntity(studentID: studentID, completedAt: normalized, work: self))
        }
    }

    func ensureParticipantsFromStudentIDs() {
        // Ensure participants mirror studentIDs, preserving any existing completion dates
        let currentIDs = Set(participants.map { $0.studentID })
        let targetIDs = Set(studentIDs)
        // Add missing
        for id in targetIDs.subtracting(currentIDs) {
            participants.append(WorkParticipantEntity(studentID: id, work: self))
        }
        // Remove extras (students removed from work)
        participants.removeAll { !targetIDs.contains($0.studentID) }
    }
}

