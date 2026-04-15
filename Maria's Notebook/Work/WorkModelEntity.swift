import Foundation
import CoreData

@objc(CDWorkModel)
public class CDWorkModel: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var workTypeRaw: String
    @NSManaged public var studentLessonID: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var completedAt: Date?
    @NSManaged public var kindRaw: String?
    @NSManaged public var statusRaw: String
    @NSManaged public var assignedAt: Date?
    @NSManaged public var lastTouchedAt: Date?
    @NSManaged public var dueAt: Date?
    @NSManaged public var completionOutcomeRaw: String?
    @NSManaged public var legacyContractID: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var lessonID: String
    @NSManaged public var presentationID: String?
    @NSManaged public var trackID: String?
    @NSManaged public var trackStepID: String?
    @NSManaged public var scheduledNote: String?
    @NSManaged public var scheduledReasonRaw: String?
    @NSManaged public var sourceContextTypeRaw: String?
    @NSManaged public var sourceContextID: String?
    @NSManaged public var sampleWorkID: String?
    @NSManaged public var legacyStudentLessonID: String?
    @NSManaged public var checkInStyleRaw: String?
    @NSManaged public var restingUntil: Date?

    // MARK: - Relationships
    @NSManaged public var participants: NSSet?
    @NSManaged public var checkIns: NSSet?
    @NSManaged public var steps: NSSet?
    @NSManaged public var unifiedNotes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "WorkModel", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.workTypeRaw = "Research"
        self.studentLessonID = nil
        self.createdAt = Date()
        self.completedAt = nil
        self.kindRaw = nil
        self.statusRaw = WorkStatus.active.rawValue
        self.assignedAt = Date()
        self.lastTouchedAt = nil
        self.dueAt = nil
        self.completionOutcomeRaw = nil
        self.legacyContractID = nil
        self.studentID = ""
        self.lessonID = ""
        self.presentationID = nil
        self.trackID = nil
        self.trackStepID = nil
        self.scheduledNote = nil
        self.scheduledReasonRaw = nil
        self.sourceContextTypeRaw = nil
        self.sourceContextID = nil
        self.sampleWorkID = nil
        self.legacyStudentLessonID = nil
        self.checkInStyleRaw = nil
        self.restingUntil = nil
    }
}

// MARK: - Computed Properties

extension CDWorkModel {
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

    // MARK: - Resting

    /// Whether this work is intentionally resting (aging paused until `restingUntil`).
    var isResting: Bool {
        guard let until = restingUntil else { return false }
        return until > AppCalendar.startOfDay(Date())
    }

    // MARK: - Completion helpers
    var isCompleted: Bool { completedAt != nil }

    /// A work item is considered open if any participant has not completed their work.
    var isOpen: Bool {
        if status == .complete { return false }
        let parts = (participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        if parts.isEmpty { return true }
        return parts.contains { $0.completedAt == nil }
    }

    // MARK: - Status Helpers

    var isActive: Bool { status == .active }
    var isReview: Bool { status == .review }
    var isComplete: Bool { status == .complete }
    var isIncomplete: Bool { status == .active || status == .review }

    func participant(for studentID: UUID) -> CDWorkParticipantEntity? {
        let studentIDString = studentID.uuidString
        let parts = (participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        return parts.first { $0.studentID == studentIDString }
    }

    func isStudentCompleted(_ studentID: UUID) -> Bool {
        return participant(for: studentID)?.completedAt != nil
    }

    // MARK: - Step Helpers

    /// Returns steps sorted by orderIndex
    var orderedSteps: [CDWorkStep] {
        let s = (steps?.allObjects as? [CDWorkStep]) ?? []
        return s.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Returns true if all steps are completed (or if there are no steps)
    var allStepsCompleted: Bool {
        let s = (steps?.allObjects as? [CDWorkStep]) ?? []
        guard !s.isEmpty else { return true }
        return s.allSatisfy { $0.completedAt != nil }
    }

    /// Returns step completion progress as (completed, total)
    var stepProgress: (completed: Int, total: Int) {
        let s = (steps?.allObjects as? [CDWorkStep]) ?? []
        let completed = s.filter { $0.completedAt != nil }.count
        return (completed, s.count)
    }

    /// Returns true if this is a report-type work
    var isReport: Bool {
        kind == .report
    }

    // MARK: - Practice Count

    /// Number of check-ins recorded for this work item, representing practice repetitions.
    var practiceCount: Int {
        (checkIns?.allObjects as? [CDWorkCheckIn])?.count ?? 0
    }

    // MARK: - Choice Mode Helpers

    /// For choice mode: returns true if this work has no participants yet
    var isOffered: Bool {
        let parts = (participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        return parts.isEmpty
    }

    /// For choice mode: returns student IDs who have selected this work
    var selectedStudentIDs: [String] {
        let parts = (participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        return parts.map(\.studentID)
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDWorkModel {
    @objc(addParticipantsObject:)
    @NSManaged public func addToParticipants(_ value: CDWorkParticipantEntity)

    @objc(removeParticipantsObject:)
    @NSManaged public func removeFromParticipants(_ value: CDWorkParticipantEntity)

    @objc(addParticipants:)
    @NSManaged public func addToParticipants(_ values: NSSet)

    @objc(removeParticipants:)
    @NSManaged public func removeFromParticipants(_ values: NSSet)

    @objc(addCheckInsObject:)
    @NSManaged public func addToCheckIns(_ value: CDWorkCheckIn)

    @objc(removeCheckInsObject:)
    @NSManaged public func removeFromCheckIns(_ value: CDWorkCheckIn)

    @objc(addCheckIns:)
    @NSManaged public func addToCheckIns(_ values: NSSet)

    @objc(removeCheckIns:)
    @NSManaged public func removeFromCheckIns(_ values: NSSet)

    @objc(addStepsObject:)
    @NSManaged public func addToSteps(_ value: CDWorkStep)

    @objc(removeStepsObject:)
    @NSManaged public func removeFromSteps(_ value: CDWorkStep)

    @objc(addSteps:)
    @NSManaged public func addToSteps(_ values: NSSet)

    @objc(removeSteps:)
    @NSManaged public func removeFromSteps(_ values: NSSet)

    @objc(addUnifiedNotesObject:)
    @NSManaged public func addToUnifiedNotes(_ value: CDNote)

    @objc(removeUnifiedNotesObject:)
    @NSManaged public func removeFromUnifiedNotes(_ value: CDNote)

    @objc(addUnifiedNotes:)
    @NSManaged public func addToUnifiedNotes(_ values: NSSet)

    @objc(removeUnifiedNotes:)
    @NSManaged public func removeFromUnifiedNotes(_ values: NSSet)
}
