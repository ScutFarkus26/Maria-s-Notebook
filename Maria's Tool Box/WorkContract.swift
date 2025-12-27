import Foundation
import SwiftData

enum WorkKind: String, Codable, CaseIterable {
    case practiceLesson
    case followUpAssignment
    case research
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
    
    // NEW: specific title for this work (e.g. "Diorama")
    var title: String?

    // New lightweight fields
    var kindRaw: String?
    var nextCheckInDate: Date?
    var scheduledReasonRaw: String?
    var scheduledNote: String?
    var dueDate: Date?
    var completionOutcomeRaw: String?
    var completionNote: String?

    // Source context
    var sourceContextTypeRaw: String?
    var sourceContextID: String?

    // Legacy linkage
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
        legacyStudentLessonID: String? = nil
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

        // Default kind based on creation source
        if let presentationID, !presentationID.isEmpty {
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

    var scheduledReason: ScheduledReason? {
        get { scheduledReasonRaw.flatMap { ScheduledReason(rawValue: $0) } }
        set { scheduledReasonRaw = newValue?.rawValue }
    }

    var completionOutcome: CompletionOutcome? {
        get { completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0) } }
        set { completionOutcomeRaw = newValue?.rawValue }
    }

    var sourceContextType: WorkSourceContextType? {
        get { sourceContextTypeRaw.flatMap { WorkSourceContextType(rawValue: $0) } }
        set { sourceContextTypeRaw = newValue?.rawValue }
    }

    var isOpen: Bool { status != .complete }
}

extension WorkContract {
    func lastMeaningfulTouchDate(planItems: [WorkPlanItem], notes: [ScopedNote], presentation: Presentation? = nil) -> Date {
        WorkContractAging.lastMeaningfulTouchDate(for: self, planItems: planItems, notes: notes, presentation: presentation)
    }

    func daysSinceLastTouch(modelContext: ModelContext, planItems: [WorkPlanItem], notes: [ScopedNote], presentation: Presentation? = nil) -> Int {
        WorkContractAging.daysSinceLastTouch(for: self, modelContext: modelContext, planItems: planItems, notes: notes, presentation: presentation)
    }

    func agingBucket(modelContext: ModelContext, planItems: [WorkPlanItem], notes: [ScopedNote], presentation: Presentation? = nil) -> AgingBucket {
        WorkContractAging.agingBucket(for: self, modelContext: modelContext, planItems: planItems, notes: notes, presentation: presentation)
    }

    func isStale(modelContext: ModelContext, planItems: [WorkPlanItem], notes: [ScopedNote], presentation: Presentation? = nil) -> Bool {
        WorkContractAging.isStale(self, modelContext: modelContext, planItems: planItems, notes: notes, presentation: presentation)
    }

    func isOverdue(planItems: [WorkPlanItem], lastTouch: Date? = nil) -> Bool {
        WorkContractAging.isOverdue(self, planItems: planItems, lastTouch: lastTouch)
    }
}
