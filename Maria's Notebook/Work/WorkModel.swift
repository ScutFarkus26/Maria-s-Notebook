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
    @Relationship(deleteRule: .cascade, inverse: \Note.work) var unifiedNotes: [Note]? = []
    
    // MARK: - Core Work Fields
    /// Work kind (practice, follow-up, research)
    var kindRaw: String? = nil
    /// Work status (active, review, complete)
    var statusRaw: String = WorkStatus.active.rawValue
    /// When the work was assigned (defaults to createdAt if not set)
    var assignedAt: Date = Date()
    /// Last meaningful touch date (for aging calculations)
    var lastTouchedAt: Date? = nil
    /// Due date for the work
    var dueAt: Date? = nil
    /// Completion outcome (mastered, needsReview, etc.)
    var completionOutcomeRaw: String? = nil
    /// Legacy contract ID for traceability (from migration)
    var legacyContractID: UUID? = nil
    /// Student ID (CloudKit compatible string)
    var studentID: String = ""
    /// Lesson ID (CloudKit compatible string)
    var lessonID: String = ""
    /// Presentation ID (optional, CloudKit compatible string)
    var presentationID: String? = nil
    /// Track ID (optional, CloudKit compatible string)
    var trackID: String? = nil
    /// Track step ID (optional, CloudKit compatible string)
    var trackStepID: String? = nil
    /// Scheduled note
    var scheduledNote: String? = nil
    /// Scheduled reason raw value
    var scheduledReasonRaw: String? = nil
    /// Source context type raw value (e.g., projectSession)
    var sourceContextTypeRaw: String? = nil
    /// Source context ID (e.g., project session ID)
    var sourceContextID: String? = nil
    /// Legacy student lesson ID for traceability
    var legacyStudentLessonID: String? = nil

    init(
        id: UUID = UUID(),
        title: String = "",
        workType: WorkType = .research,
        studentLessonID: UUID? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        participants: [WorkParticipantEntity] = [],
        // Migration-ready parameters
        kind: WorkKind? = nil,
        status: WorkStatus = .active,
        assignedAt: Date? = nil,
        lastTouchedAt: Date? = nil,
        dueAt: Date? = nil,
        completionOutcome: CompletionOutcome? = nil,
        legacyContractID: UUID? = nil,
        studentID: String = "",
        lessonID: String = "",
        presentationID: String? = nil,
        trackID: String? = nil,
        trackStepID: String? = nil,
        scheduledNote: String? = nil,
        scheduledReason: ScheduledReason? = nil,
        sourceContextType: WorkSourceContextType? = nil,
        sourceContextID: String? = nil,
        legacyStudentLessonID: String? = nil
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
        self.unifiedNotes = []
        for p in (self.participants ?? []) { p.work = self }
        
        // Migration-ready fields
        self.kindRaw = kind?.rawValue
        self.statusRaw = status.rawValue
        self.assignedAt = assignedAt ?? createdAt
        self.lastTouchedAt = lastTouchedAt
        self.dueAt = dueAt
        self.completionOutcomeRaw = completionOutcome?.rawValue
        self.legacyContractID = legacyContractID
        self.studentID = studentID
        self.lessonID = lessonID
        self.presentationID = presentationID
        self.trackID = trackID
        self.trackStepID = trackStepID
        self.scheduledNote = scheduledNote
        self.scheduledReasonRaw = scheduledReason?.rawValue
        self.sourceContextTypeRaw = sourceContextType?.rawValue
        self.sourceContextID = sourceContextID
        self.legacyStudentLessonID = legacyStudentLessonID
    }

    var workType: WorkType {
        get { WorkType(rawValue: workTypeRaw) ?? .research }
        set { workTypeRaw = newValue.rawValue }
    }
    
    // MARK: - Computed Properties

    /// Work kind (practice, follow-up, research)
    var kind: WorkKind? {
        get { kindRaw.flatMap { WorkKind(rawValue: $0) } }
        set { kindRaw = newValue?.rawValue }
    }

    /// Work status (active, review, complete)
    var status: WorkStatus {
        get { WorkStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    /// Completion outcome (mastered, needsReview, etc.)
    var completionOutcome: CompletionOutcome? {
        get { completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0) } }
        set { completionOutcomeRaw = newValue?.rawValue }
    }

    /// Scheduled reason
    var scheduledReason: ScheduledReason? {
        get { scheduledReasonRaw.flatMap { ScheduledReason(rawValue: $0) } }
        set { scheduledReasonRaw = newValue?.rawValue }
    }

    /// Source context type (e.g., projectSession)
    var sourceContextType: WorkSourceContextType? {
        get { sourceContextTypeRaw.flatMap { WorkSourceContextType(rawValue: $0) } }
        set { sourceContextTypeRaw = newValue?.rawValue }
    }

    // MARK: - Completion helpers
    var isCompleted: Bool { completedAt != nil }

    /// A work item is considered open if any participant has not completed their work.
    /// If there are no participants, treat it as open so it appears in triage lists.
    var isOpen: Bool {
        if status == .complete { return false }
        // If no participants have been assigned, consider it open
        if (participants ?? []).isEmpty { return true }
        // Otherwise open if any participant has not completed
        return (participants ?? []).contains { $0.completedAt == nil }
    }

    // MARK: - Status Helpers
    
    /// Convenience computed properties for status checks (not usable in predicates)
    var isActive: Bool { status == .active }
    var isReview: Bool { status == .review }
    var isComplete: Bool { status == .complete }
    var isIncomplete: Bool { status == .active || status == .review }

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
