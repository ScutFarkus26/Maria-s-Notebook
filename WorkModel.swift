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

    init(
        id: UUID = UUID(),
        studentIDs: [UUID] = [],
        workType: WorkType = .research,
        studentLessonID: UUID? = nil,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.studentIDs = studentIDs
        self.workTypeRaw = workType.rawValue
        self.studentLessonID = studentLessonID
        self.notes = notes
        self.createdAt = createdAt
    }

    var workType: WorkType {
        get { WorkType(rawValue: workTypeRaw) ?? .research }
        set { workTypeRaw = newValue.rawValue }
    }
}

