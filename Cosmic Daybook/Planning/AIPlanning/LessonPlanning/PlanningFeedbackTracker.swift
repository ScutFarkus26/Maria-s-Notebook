import Foundation
import CoreData
import OSLog

/// Records teacher decisions on AI recommendations and tracks outcomes.
/// Provides calibration data for future planning prompts by analyzing
/// patterns in accepted/rejected recommendations.
struct PlanningFeedbackTracker {
    private static let logger = Logger.ai

    // MARK: - Record Decisions (Core Data)

    /// Records a teacher decision on a recommendation.
    static func recordDecision(
        recommendation: LessonRecommendation,
        decision: TeacherDecision,
        session: PlanningSession,
        teacherNote: String? = nil,
        context: NSManagedObjectContext
    ) {
        let record = CDPlanningRecommendation(context: context)
        record.id = UUID()
        record.lessonID = recommendation.lessonID.uuidString
        record.studentIDs = recommendation.studentIDs.map(\.uuidString)
        record.reasoning = recommendation.reasoning
        record.confidence = recommendation.confidence
        record.priority = Int64(recommendation.priority)
        record.subjectContext = recommendation.area
        record.groupContext = recommendation.sequence
        record.planningSessionID = session.id.uuidString
        record.depthLevel = session.depth.rawValue
        record.decisionRaw = decision.rawValue
        record.teacherNote = teacherNote
        record.createdAt = Date()
        record.modifiedAt = Date()

        Self.logger.info("Recorded \(decision.rawValue) decision for \(recommendation.lessonName)")
    }

}
