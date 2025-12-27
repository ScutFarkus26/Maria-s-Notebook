import Foundation
import SwiftData

enum WorkKind: String, Codable, CaseIterable {
    case practiceLesson
    case followUpAssignment
    case research // UI Label: "Project"
}

enum ScheduledReason: String, Codable, CaseIterable {
    case progressCheck
    case dueDate
    case conference
    case reminder
    case other
}

enum CompletionOutcome: String, Codable, CaseIterable {
    case mastered
    case submitted
    case needsMorePractice
    case paused
    case notRequired
}

enum WorkStatus: String, Codable, CaseIterable {
    case active, review, complete
}

enum WorkSourceContextType: String, Codable {
    case bookClubSession
}

@Model
final class WorkContract: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var studentID: String
    var lessonID: String
    var presentationID: String?
    
    var title: String?
    var statusRaw: String
    var scheduledDate: Date?
    var completedAt: Date?

    var kindRaw: String?
    var completionOutcomeRaw: String?
    var completionNote: String?
    
    // Metadata for specific contexts
    var sourceContextTypeRaw: String?
    var sourceContextID: String?
    var scheduledNote: String?
    
    // NEW: Storage for the reason (Fixes BackupService errors)
    var scheduledReasonRaw: String?
    
    // Legacy support
    var legacyStudentLessonID: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        studentID: String,
        lessonID: String,
        presentationID: String? = nil,
        title: String? = nil,
        status: WorkStatus = .active,
        scheduledDate: Date? = nil,
        completedAt: Date? = nil,
        legacyStudentLessonID: String? = nil,
        kind: WorkKind? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.studentID = studentID
        self.lessonID = lessonID
        self.presentationID = presentationID
        self.title = title
        self.statusRaw = status.rawValue
        self.scheduledDate = scheduledDate
        self.completedAt = completedAt
        self.legacyStudentLessonID = legacyStudentLessonID

        if let kind {
            self.kindRaw = kind.rawValue
        } else if let presentationID, !presentationID.isEmpty {
            self.kindRaw = WorkKind.practiceLesson.rawValue
        } else {
            self.kindRaw = WorkKind.followUpAssignment.rawValue
        }
    }

    var status: WorkStatus {
        get { WorkStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var kind: WorkKind? {
        get { kindRaw.flatMap { WorkKind(rawValue: $0) } }
        set { kindRaw = newValue?.rawValue }
    }

    var completionOutcome: CompletionOutcome? {
        get { completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0) } }
        set { completionOutcomeRaw = newValue?.rawValue }
    }
    
    // NEW: Computed property for BackupService usage
    var scheduledReason: ScheduledReason? {
        get { scheduledReasonRaw.flatMap { ScheduledReason(rawValue: $0) } }
        set { scheduledReasonRaw = newValue?.rawValue }
    }

    var sourceContextType: WorkSourceContextType? {
        get { sourceContextTypeRaw.flatMap { WorkSourceContextType(rawValue: $0) } }
        set { sourceContextTypeRaw = newValue?.rawValue }
    }

    var isOpen: Bool { status != .complete }
}
