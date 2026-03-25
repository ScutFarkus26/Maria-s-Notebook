import Foundation
import SwiftData
import SwiftUI

@Model final class WorkModel: Identifiable {
    // Modern compound indexes for 2026 - optimized for common query patterns
    // Multiple indexes defined in one #Index macro (SwiftData limitation)
    // Compound indexes improve query performance for multi-field lookups
    #Index<WorkModel>(
        [\.studentID, \.statusRaw],
        [\.statusRaw, \.dueAt],
        [\.statusRaw, \.assignedAt],
        [\.presentationID],
        [\.completedAt]
    )
    
    @available(*, deprecated, message: "Use WorkKind instead. WorkType is maintained for backwards compatibility only.")
    enum WorkType: String, CaseIterable, Codable, Sendable {
        case research = "Research"
        case followUp = "Follow Up"
        case practice = "Practice"
        case report = "Report"
    }

    var id: UUID = UUID()
    var title: String = ""
    // DEPRECATED: workTypeRaw is maintained for data migration only
    // New code should use kindRaw. After migration completes, workType reads from kind.
    private(set) var workTypeRaw: String = "Research"
    var studentLessonID: UUID?
    var createdAt: Date = Date()
    var completedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \WorkParticipantEntity.work)
    var participants: [WorkParticipantEntity]? = []
    @Relationship(deleteRule: .cascade, inverse: \WorkCheckIn.work) var checkIns: [WorkCheckIn]? = []
    @Relationship(deleteRule: .cascade, inverse: \WorkStep.work) var steps: [WorkStep]? = []
    // CloudKit compatibility: Relationship arrays must be optional
    @Relationship(deleteRule: .cascade, inverse: \Note.work) var unifiedNotes: [Note]? = []
    
    // MARK: - Core Work Fields
    /// Work kind (practice, follow-up, research)
    var kindRaw: String?
    /// Work status (active, review, complete) - indexed for frequent filtering
    var statusRaw: String = WorkStatus.active.rawValue
    /// When the work was assigned (defaults to createdAt if not set)
    var assignedAt: Date = Date()
    /// Last meaningful touch date (for aging calculations)
    var lastTouchedAt: Date?
    /// Due date for the work - indexed for date range queries
    var dueAt: Date?
    /// Completion outcome (mastered, needsReview, etc.)
    var completionOutcomeRaw: String?
    /// Legacy contract ID for traceability (from migration)
    var legacyContractID: UUID?
    /// Student ID (CloudKit compatible string) - indexed for student-specific queries
    var studentID: String = ""
    /// Lesson ID (CloudKit compatible string)
    var lessonID: String = ""
    /// Presentation ID (optional, CloudKit compatible string)
    var presentationID: String?
    /// Track ID (optional, CloudKit compatible string)
    var trackID: String?
    /// Track step ID (optional, CloudKit compatible string)
    var trackStepID: String?
    /// Scheduled note
    var scheduledNote: String?
    /// Scheduled reason raw value
    var scheduledReasonRaw: String?
    /// Source context type raw value (e.g., projectSession)
    var sourceContextTypeRaw: String?
    /// Source context ID (e.g., project session ID)
    var sourceContextID: String?
    /// ID of the SampleWork template this work was created from (optional reference, not a relationship)
    var sampleWorkID: String?
    /// Legacy assignment ID for traceability
    var legacyStudentLessonID: String?
    /// Check-in style: how multi-student work check-ins are displayed (individual, group, flexible)
    var checkInStyleRaw: String?

    init(
        id: UUID = UUID(),
        title: String = "",
        kind: WorkKind = .research,
        studentLessonID: UUID? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        participants: [WorkParticipantEntity] = [],
        // Migration-ready parameters
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
        self.workTypeRaw = Self.legacyWorkTypeRaw(for: kind)
        self.studentLessonID = studentLessonID
        // Use AppCalendar.shared for consistent date normalization across the app
        self.createdAt = AppCalendar.startOfDay(createdAt)
        self.completedAt = completedAt.map { AppCalendar.startOfDay($0) }
        self.participants = participants
        self.unifiedNotes = []
        for p in (self.participants ?? []) { p.work = self }
        
        // Migration-ready fields
        self.kindRaw = kind.rawValue
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

    /// Maps WorkKind to the legacy workTypeRaw string without going through deprecated WorkType.
    private static func legacyWorkTypeRaw(for kind: WorkKind) -> String {
        switch kind {
        case .practiceLesson: "Practice"
        case .followUpAssignment: "Follow Up"
        case .research: "Research"
        case .report: "Report"
        }
    }

    // swiftlint:disable:next line_length
    /// DEPRECATED: Use `kind` instead. This property is maintained for backwards compatibility. After data migration, workType reads from kind and converts to the legacy enum format.
    @available(
        *, deprecated,
        message: "Use 'kind' (WorkKind) instead. WorkType is maintained for backwards compatibility only."
    )
    var workType: WorkType {
        get {
            // After migration, prefer kind over workTypeRaw
            if let k = kind {
                return k.asWorkType
            }
            // Fallback to legacy workTypeRaw during migration
            return WorkType(rawValue: workTypeRaw) ?? .research
        }
        set {
            // Write to both systems during migration for safety
            workTypeRaw = newValue.rawValue
            kind = switch newValue {
            case .practice: .practiceLesson
            case .followUp: .followUpAssignment
            case .research: .research
            case .report: .report
            }
        }
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

    /// Check-in style for multi-student work (individual, group, flexible)
    var checkInStyle: CheckInStyle {
        get { checkInStyleRaw.flatMap { CheckInStyle(rawValue: $0) } ?? .flexible }
        set { checkInStyleRaw = newValue.rawValue }
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

    // REMOVED: markStudent() method
    // Use WorkCompletionService.markCompleted() instead for proper historical tracking
    // For direct participant manipulation, access participant(for:) and set completedAt directly

    // MARK: - Step Helpers

    /// Returns steps sorted by orderIndex
    var orderedSteps: [WorkStep] {
        (steps ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Returns true if all steps are completed (or if there are no steps)
    var allStepsCompleted: Bool {
        let s = steps ?? []
        guard !s.isEmpty else { return true }
        return s.allSatisfy { $0.completedAt != nil }
    }

    /// Returns step completion progress as (completed, total)
    var stepProgress: (completed: Int, total: Int) {
        let s = steps ?? []
        let completed = s.filter { $0.completedAt != nil }.count
        return (completed, s.count)
    }

    /// Returns true if this is a report-type work
    var isReport: Bool {
        kind == .report
    }

    // MARK: - Choice Mode Helpers

    /// For choice mode: returns true if this work has no participants yet (offered but not selected)
    var isOffered: Bool {
        (participants ?? []).isEmpty
    }

    /// For choice mode: returns student IDs who have selected this work
    var selectedStudentIDs: [String] {
        (participants ?? []).map(\.studentID)
    }
}
