import Foundation
import SwiftData
import OSLog

/// Records teacher decisions on AI recommendations and tracks outcomes.
/// Provides calibration data for future planning prompts by analyzing
/// patterns in accepted/rejected recommendations.
@MainActor
struct PlanningFeedbackTracker {
    private static let logger = Logger.ai
    
    // MARK: - Record Decisions
    
    /// Records a teacher decision on a recommendation.
    static func recordDecision(
        recommendation: LessonRecommendation,
        decision: TeacherDecision,
        session: PlanningSession,
        teacherNote: String? = nil,
        modelContext: ModelContext
    ) {
        let record = PlanningRecommendation(
            lessonID: recommendation.lessonID,
            studentIDs: recommendation.studentIDs,
            reasoning: recommendation.reasoning,
            confidence: recommendation.confidence,
            priority: recommendation.priority,
            subjectContext: recommendation.subject,
            groupContext: recommendation.group,
            planningSessionID: session.id,
            depthLevel: session.depth
        )
        
        record.decision = decision
        record.teacherNote = teacherNote
        
        modelContext.insert(record)
        
        Self.logger.info("Recorded \(decision.rawValue) decision for \(recommendation.lessonName)")
    }
    
    /// Links an accepted recommendation to its created LessonAssignment.
    static func linkToPresentation(
        recommendationID: UUID,
        presentationID: UUID,
        modelContext: ModelContext
    ) {
        let idStr = recommendationID.uuidString
        let descriptor = FetchDescriptor<PlanningRecommendation>(
            predicate: #Predicate<PlanningRecommendation> { rec in
                rec.id.uuidString == idStr
            }
        )
        
        guard let record = (try? modelContext.fetch(descriptor))?.first else {
            Self.logger.warning("PlanningRecommendation not found for linking: \(recommendationID)")
            return
        }
        
        record.presentationID = presentationID.uuidString
        record.modifiedAt = Date()
    }
    
    /// Records the outcome after a recommendation was applied.
    static func recordOutcome(
        recommendationID: UUID,
        outcome: RecommendationOutcome,
        modelContext: ModelContext
    ) {
        let idStr = recommendationID.uuidString
        let descriptor = FetchDescriptor<PlanningRecommendation>(
            predicate: #Predicate<PlanningRecommendation> { rec in
                rec.id.uuidString == idStr
            }
        )
        
        guard let record = (try? modelContext.fetch(descriptor))?.first else { return }
        record.outcome = outcome
    }
    
    // MARK: - Calibration Data
    
    /// Fetches calibration data summarizing past teacher decisions for prompt enrichment.
    /// Returns a string suitable for including in planning prompts.
    static func calibrationSummary(modelContext: ModelContext) -> String? {
        let descriptor = FetchDescriptor<PlanningRecommendation>(
            sortBy: [SortDescriptor(\PlanningRecommendation.createdAt, order: .reverse)]
        )
        
        guard let records = try? modelContext.fetch(descriptor), !records.isEmpty else {
            return nil
        }
        
        // Aggregate decision patterns
        var acceptedSubjects: [String: Int] = [:]
        var rejectedSubjects: [String: Int] = [:]
        var totalAccepted = 0
        var totalRejected = 0
        
        for record in records {
            switch record.decision {
            case .accepted:
                totalAccepted += 1
                acceptedSubjects[record.subjectContext, default: 0] += 1
            case .rejected:
                totalRejected += 1
                rejectedSubjects[record.subjectContext, default: 0] += 1
            default:
                break
            }
        }
        
        guard totalAccepted + totalRejected > 5 else { return nil }
        
        var lines: [String] = []
        lines.append("TEACHER PREFERENCE CALIBRATION (from \(records.count) past recommendations):")
        lines.append("Acceptance rate: \(totalAccepted)/\(totalAccepted + totalRejected)")
        
        // Most accepted subjects
        let topAccepted = acceptedSubjects.sorted { $0.value > $1.value }.prefix(3)
        if !topAccepted.isEmpty {
            lines.append("Frequently accepted subjects: \(topAccepted.map { "\($0.key)(\($0.value))" }.joined(separator: ", "))")
        }
        
        // Most rejected subjects
        let topRejected = rejectedSubjects.sorted { $0.value > $1.value }.prefix(3)
        if !topRejected.isEmpty {
            lines.append("Frequently rejected subjects: \(topRejected.map { "\($0.key)(\($0.value))" }.joined(separator: ", "))")
        }
        
        // Teacher notes patterns
        let notes = records.compactMap { $0.teacherNote }.filter { !$0.isEmpty }
        if !notes.isEmpty {
            lines.append("Recent teacher notes: \(notes.prefix(3).joined(separator: "; "))")
        }
        
        return lines.joined(separator: "\n")
    }
}
