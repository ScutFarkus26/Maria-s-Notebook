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

    // New lightweight fields (additive; optional for backward compatibility)
    var kindRaw: String?
    var nextCheckInDate: Date?
    var scheduledReasonRaw: String?
    var scheduledNote: String?
    var dueDate: Date?
    var completionOutcomeRaw: String?
    var completionNote: String?

    // Source context (additive; optional)
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

        // Default kind based on creation source (presentation → practice; otherwise follow-up)
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
    /// Most recent meaningful touch date using provided plan items and notes.
    func lastMeaningfulTouchDate(planItems: [WorkPlanItem], notes: [ScopedNote], presentation: Presentation? = nil) -> Date {
        WorkContractAging.lastMeaningfulTouchDate(for: self, planItems: planItems, notes: notes, presentation: presentation)
    }

    /// Day count since last meaningful touch (school-day aware).
    func daysSinceLastTouch(modelContext: ModelContext, planItems: [WorkPlanItem], notes: [ScopedNote], presentation: Presentation? = nil) -> Int {
        WorkContractAging.daysSinceLastTouch(for: self, modelContext: modelContext, planItems: planItems, notes: notes, presentation: presentation)
    }

    /// Aging bucket classification (school-day aware).
    func agingBucket(modelContext: ModelContext, planItems: [WorkPlanItem], notes: [ScopedNote], presentation: Presentation? = nil) -> AgingBucket {
        WorkContractAging.agingBucket(for: self, modelContext: modelContext, planItems: planItems, notes: notes, presentation: presentation)
    }

    /// Convenience for stale status (school-day aware).
    func isStale(modelContext: ModelContext, planItems: [WorkPlanItem], notes: [ScopedNote], presentation: Presentation? = nil) -> Bool {
        WorkContractAging.isStale(self, modelContext: modelContext, planItems: planItems, notes: notes, presentation: presentation)
    }

    /// Intent-aware overdue: uses only plan items (progress/assessment) and an optional override for last touch.
    func isOverdue(planItems: [WorkPlanItem], lastTouch: Date? = nil) -> Bool {
        WorkContractAging.isOverdue(self, planItems: planItems, lastTouch: lastTouch)
    }
}

#if DEBUG
extension WorkContract {
    var debugDescription: String {
        return "WorkContract(id=\(id), student=\(studentID.prefix(8))…, lesson=\(lessonID.prefix(8))…, status=\(statusRaw), scheduled=\(scheduledDate?.description ?? "nil"))"
    }
}
#endif

