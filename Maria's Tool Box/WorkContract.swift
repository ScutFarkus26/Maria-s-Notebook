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
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var studentID: String = ""
    var lessonID: String = ""
    var presentationID: String? = nil
    
    var title: String? = nil
    var statusRaw: String = WorkStatus.active.rawValue
    var scheduledDate: Date? = nil
    var completedAt: Date? = nil

    var kindRaw: String? = nil
    var completionOutcomeRaw: String? = nil
    var completionNote: String? = nil
    
    // Metadata for specific contexts
    var sourceContextTypeRaw: String? = nil
    var sourceContextID: String? = nil
    var scheduledNote: String? = nil
    
    // NEW: Storage for the reason (Fixes BackupService errors)
    var scheduledReasonRaw: String? = nil
    
    // Legacy support
    var legacyStudentLessonID: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \ScopedNote.workContract) var scopedNotes: [ScopedNote]? = []

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        studentID: String = "",
        lessonID: String = "",
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
        
        self.scopedNotes = []
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
