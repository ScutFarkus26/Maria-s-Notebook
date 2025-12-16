import Foundation
import SwiftData

enum WorkStatus: String, Codable, CaseIterable {
    case active, review, complete
}

/// Per-student work contract generated from a Presentation.
@Model
final class WorkContract: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    // Foreign keys stored as strings for CloudKit compatibility
    var studentID: String
    var lessonID: String
    var presentationID: String?

    // State
    var statusRaw: String
    var scheduledDate: Date?
    var completedAt: Date?

    // Legacy linkage
    var legacyStudentLessonID: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        studentID: String,
        lessonID: String,
        presentationID: String? = nil,
        status: WorkStatus = .active,
        scheduledDate: Date? = nil,
        completedAt: Date? = nil,
        legacyStudentLessonID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.studentID = studentID
        self.lessonID = lessonID
        self.presentationID = presentationID
        self.statusRaw = status.rawValue
        self.scheduledDate = scheduledDate
        self.completedAt = completedAt
        self.legacyStudentLessonID = legacyStudentLessonID
    }

    var status: WorkStatus {
        get { WorkStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var isOpen: Bool { status != .complete }
}

#if DEBUG
extension WorkContract {
    var debugDescription: String {
        return "WorkContract(id=\(id), student=\(studentID.prefix(8))…, lesson=\(lessonID.prefix(8))…, status=\(statusRaw), scheduled=\(scheduledDate?.description ?? "nil"))"
    }
}
#endif
