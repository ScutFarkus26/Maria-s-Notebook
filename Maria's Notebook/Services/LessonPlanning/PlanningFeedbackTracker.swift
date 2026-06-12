import Foundation
import CoreData
import OSLog

/// Records teacher decisions on AI recommendations and tracks outcomes.
/// Provides calibration data for future planning prompts by analyzing
/// patterns in accepted/rejected recommendations.
@MainActor
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

    // MARK: - Shared Helpers

    // Deprecated SwiftData methods removed - use Core Data overloads.

    private static func buildCalibrationSummary(from records: [CDPlanningRecommendation]) -> String? {
        // Aggregate decision patterns
        var acceptedAreas: [String: Int] = [:]
        var rejectedAreas: [String: Int] = [:]
        var totalAccepted = 0
        var totalRejected = 0

        for record in records {
            switch record.decision {
            case .accepted:
                totalAccepted += 1
                acceptedAreas[record.subjectContext, default: 0] += 1
            case .rejected:
                totalRejected += 1
                rejectedAreas[record.subjectContext, default: 0] += 1
            default:
                break
            }
        }

        guard totalAccepted + totalRejected > 5 else { return nil }

        var lines: [String] = []
        lines.append("TEACHER PREFERENCE CALIBRATION (from \(records.count) past recommendations):")
        lines.append("Acceptance rate: \(totalAccepted)/\(totalAccepted + totalRejected)")

        // Most accepted areas
        let topAccepted = acceptedAreas.sorted { $0.value > $1.value }.prefix(3)
        if !topAccepted.isEmpty {
            let acceptedList = topAccepted.map { "\($0.key)(\($0.value))" }.joined(separator: ", ")
            lines.append("Frequently accepted areas: \(acceptedList)")
        }

        // Most rejected areas
        let topRejected = rejectedAreas.sorted { $0.value > $1.value }.prefix(3)
        if !topRejected.isEmpty {
            let rejectedList = topRejected.map { "\($0.key)(\($0.value))" }.joined(separator: ", ")
            lines.append("Frequently rejected areas: \(rejectedList)")
        }

        // Teacher notes patterns
        let notes = records.compactMap(\.teacherNote).filter { !$0.isEmpty }
        if !notes.isEmpty {
            lines.append("Recent teacher notes: \(notes.prefix(3).joined(separator: "; "))")
        }

        return lines.joined(separator: "\n")
    }
}
