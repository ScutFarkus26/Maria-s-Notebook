import Foundation
import CoreData
import SwiftData
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
        record.subjectContext = recommendation.subject
        record.groupContext = recommendation.group
        record.planningSessionID = session.id.uuidString
        record.depthLevel = session.depth.rawValue
        record.decisionRaw = decision.rawValue
        record.teacherNote = teacherNote
        record.createdAt = Date()
        record.modifiedAt = Date()

        Self.logger.info("Recorded \(decision.rawValue) decision for \(recommendation.lessonName)")
    }

    /// Links an accepted recommendation to its created LessonAssignment.
    static func linkToPresentation(
        recommendationID: UUID,
        presentationID: UUID,
        context: NSManagedObjectContext
    ) {
        let request = CDFetchRequest(CDPlanningRecommendation.self)
        request.predicate = NSPredicate(format: "id == %@", recommendationID as CVarArg)

        guard let record = context.safeFetch(request).first else {
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
        context: NSManagedObjectContext
    ) {
        let request = CDFetchRequest(CDPlanningRecommendation.self)
        request.predicate = NSPredicate(format: "id == %@", recommendationID as CVarArg)

        guard let record = context.safeFetch(request).first else { return }
        record.outcomeRaw = outcome.rawValue
    }

    // MARK: - Calibration Data (Core Data)

    /// Fetches calibration data summarizing past teacher decisions for prompt enrichment.
    /// Returns a string suitable for including in planning prompts.
    static func calibrationSummary(context: NSManagedObjectContext) -> String? {
        // Use SwiftData to fetch PlanningRecommendation (same SQLite store).
        // Full CD conversion happens when PlanningRecommendation model is converted.
        let modelContext = AppBootstrapping.getSharedModelContainer().mainContext
        let descriptor = FetchDescriptor<PlanningRecommendation>(
            sortBy: [SortDescriptor(\PlanningRecommendation.createdAt, order: .reverse)]
        )
        guard let records = try? modelContext.fetch(descriptor), !records.isEmpty else {
            return nil
        }
        return buildCalibrationSummary(from: records)
    }

    // MARK: - Record Decisions (SwiftData — Deprecated)

    /// Records a teacher decision on a recommendation.
    @available(*, deprecated, message: "Use Core Data overload")
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
    @available(*, deprecated, message: "Use Core Data overload")
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
    @available(*, deprecated, message: "Use Core Data overload")
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

    /// Fetches calibration data summarizing past teacher decisions for prompt enrichment.
    @available(*, deprecated, message: "Use Core Data overload")
    static func calibrationSummary(modelContext: ModelContext) -> String? {
        let descriptor = FetchDescriptor<PlanningRecommendation>(
            sortBy: [SortDescriptor(\PlanningRecommendation.createdAt, order: .reverse)]
        )

        guard let records = try? modelContext.fetch(descriptor), !records.isEmpty else {
            return nil
        }

        return buildCalibrationSummary(from: records)
    }

    // MARK: - Shared Helpers

    private static func buildCalibrationSummary(from records: [PlanningRecommendation]) -> String? {
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
            let acceptedList = topAccepted.map { "\($0.key)(\($0.value))" }.joined(separator: ", ")
            lines.append("Frequently accepted subjects: \(acceptedList)")
        }

        // Most rejected subjects
        let topRejected = rejectedSubjects.sorted { $0.value > $1.value }.prefix(3)
        if !topRejected.isEmpty {
            let rejectedList = topRejected.map { "\($0.key)(\($0.value))" }.joined(separator: ", ")
            lines.append("Frequently rejected subjects: \(rejectedList)")
        }

        // Teacher notes patterns
        let notes = records.compactMap(\.teacherNote).filter { !$0.isEmpty }
        if !notes.isEmpty {
            lines.append("Recent teacher notes: \(notes.prefix(3).joined(separator: "; "))")
        }

        return lines.joined(separator: "\n")
    }
}
