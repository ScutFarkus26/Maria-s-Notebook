import Foundation
import SwiftData

/// Persists AI lesson planning recommendations and teacher decisions for feedback tracking.
/// Links recommendations to the planning session that produced them and optionally to
/// the LessonAssignment created when a recommendation is accepted.
@Model
final class PlanningRecommendation {
    // MARK: - Identity
    
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    
    // MARK: - Recommendation Content
    
    /// The lesson being recommended
    var lessonID: String = ""
    
    /// JSON-encoded array of student ID strings
    @Attribute(.externalStorage)
    var _studentIDsData: Data?
    
    /// AI-generated reasoning for this recommendation
    var reasoning: String = ""
    
    /// Confidence score (0.0 - 1.0)
    var confidence: Double = 0.0
    
    /// Priority rank within the session (1 = highest)
    var priority: Int = 0
    
    /// Subject context for grouping/display
    var subjectContext: String = ""
    
    /// Group context within the subject
    var groupContext: String = ""
    
    // MARK: - Session Context
    
    /// The planning session that generated this recommendation
    var planningSessionID: String = ""
    
    /// Depth level used when generating this recommendation
    var depthLevel: String = ""
    
    // MARK: - Teacher Decision
    
    /// Raw storage for teacher decision
    var decisionRaw: String?
    
    /// When the teacher made their decision
    var decisionAt: Date?
    
    /// Optional teacher note explaining the decision
    var teacherNote: String?
    
    // MARK: - Outcome Tracking
    
    /// Raw storage for recommendation outcome
    var outcomeRaw: String?
    
    /// When the outcome was recorded
    var outcomeRecordedAt: Date?
    
    /// ID of the LessonAssignment created when recommendation was accepted
    var presentationID: String?
    
    // MARK: - Computed Properties
    
    var studentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _studentIDsData) }
        set { _studentIDsData = CloudKitStringArrayStorage.encode(newValue) }
    }
    
    var decision: TeacherDecision? {
        get {
            guard let raw = decisionRaw else { return nil }
            return TeacherDecision(rawValue: raw)
        }
        set {
            decisionRaw = newValue?.rawValue
            if newValue != nil {
                decisionAt = Date()
                modifiedAt = Date()
            }
        }
    }
    
    var outcome: RecommendationOutcome? {
        get {
            guard let raw = outcomeRaw else { return nil }
            return RecommendationOutcome(rawValue: raw)
        }
        set {
            outcomeRaw = newValue?.rawValue
            if newValue != nil {
                outcomeRecordedAt = Date()
                modifiedAt = Date()
            }
        }
    }
    
    var lessonIDUUID: UUID? {
        UUID(uuidString: lessonID)
    }
    
    var studentUUIDs: [UUID] {
        studentIDs.compactMap { UUID(uuidString: $0) }
    }
    
    // MARK: - Initialization
    
    init(
        lessonID: UUID,
        studentIDs: [UUID],
        reasoning: String,
        confidence: Double,
        priority: Int,
        subjectContext: String,
        groupContext: String,
        planningSessionID: UUID,
        depthLevel: PlanningDepth
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.lessonID = lessonID.uuidString
        self.studentIDs = studentIDs.map { $0.uuidString }
        self.reasoning = reasoning
        self.confidence = confidence
        self.priority = priority
        self.subjectContext = subjectContext
        self.groupContext = groupContext
        self.planningSessionID = planningSessionID.uuidString
        self.depthLevel = depthLevel.rawValue
    }
}
