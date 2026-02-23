import Foundation
import SwiftData

/// Service for automatically generating follow-up work from presentations
/// Based on presentation flags like needsPractice, needsAnotherPresentation, and followUpWork notes
struct FollowUpWorkService {
    
    // MARK: - Work Generation
    
    /// Generates work items from a presentation based on its follow-up flags
    /// - Parameters:
    ///   - presentation: The presentation to generate work from
    ///   - context: SwiftData model context for creating and saving work
    /// - Returns: Array of generated work items
    @MainActor
    static func generateWorkFromPresentation(
        _ presentation: Presentation,
        context: ModelContext
    ) -> [WorkModel] {
        var workItems: [WorkModel] = []
        
        guard let lesson = presentation.lesson else {
            return workItems
        }
        
        let studentIDs = presentation.studentUUIDs
        
        // Generate practice work if needed
        if presentation.needsPractice {
            for studentID in studentIDs {
                let work = WorkModel(
                    title: "Practice: \(lesson.name)",
                    kind: .practiceLesson,
                    status: .active,
                    studentID: studentID.uuidString,
                    lessonID: presentation.lessonID,
                    presentationID: presentation.id.uuidString
                )
                context.insert(work)
                workItems.append(work)
            }
        }
        
        // Generate follow-up work if specified
        if !presentation.followUpWork.isEmpty {
            for studentID in studentIDs {
                let work = WorkModel(
                    title: presentation.followUpWork,
                    kind: .followUpAssignment,
                    status: .active,
                    studentID: studentID.uuidString,
                    lessonID: presentation.lessonID,
                    presentationID: presentation.id.uuidString
                )
                context.insert(work)
                workItems.append(work)
            }
        }
        
        // Note: needsAnotherPresentation doesn't create work items
        // It's a flag for the teacher to re-present the lesson
        
        return workItems
    }
    
    /// Generates work items for multiple presentations in batch
    /// - Parameters:
    ///   - presentations: Array of presentations to process
    ///   - context: SwiftData model context
    /// - Returns: Dictionary mapping presentation IDs to generated work items
    @MainActor
    static func batchGenerateWork(
        from presentations: [Presentation],
        context: ModelContext
    ) -> [UUID: [WorkModel]] {
        var results: [UUID: [WorkModel]] = [:]
        
        for presentation in presentations {
            let work = generateWorkFromPresentation(presentation, context: context)
            if !work.isEmpty {
                results[presentation.id] = work
            }
        }
        
        return results
    }
    
    // MARK: - Analysis
    
    /// Analyzes a presentation to determine what follow-up actions are needed
    /// - Parameter presentation: The presentation to analyze
    /// - Returns: Follow-up recommendations
    nonisolated static func analyzePresentation(_ presentation: Presentation) -> PresentationFollowUp {
        var actions: [FollowUpAction] = []
        
        if presentation.needsPractice {
            actions.append(.createPracticeWork)
        }
        
        if presentation.needsAnotherPresentation {
            actions.append(.scheduleRepresentation)
        }
        
        if !presentation.followUpWork.isEmpty {
            actions.append(.createFollowUpWork(description: presentation.followUpWork))
        }
        
        let priority: FollowUpPriority
        if presentation.needsAnotherPresentation {
            priority = .high
        } else if presentation.needsPractice {
            priority = .medium
        } else if !presentation.followUpWork.isEmpty {
            priority = .low
        } else {
            priority = .none
        }
        
        return PresentationFollowUp(
            presentationID: presentation.id,
            actions: actions,
            priority: priority,
            notes: presentation.notes
        )
    }
    
    /// Finds all presentations that need follow-up work
    /// - Parameters:
    ///   - context: SwiftData model context
    ///   - includeScheduled: Whether to include scheduled (not yet presented) presentations
    /// - Returns: Array of presentations needing follow-up
    @MainActor
    static func findPresentationsNeedingFollowUp(
        in context: ModelContext,
        includeScheduled: Bool = false
    ) -> [Presentation] {
        let stateFilter = includeScheduled ? [PresentationState.presented, .scheduled] : [.presented]
        
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { presentation in
                (presentation.needsPractice ||
                 presentation.needsAnotherPresentation ||
                 !presentation.followUpWork.isEmpty) &&
                stateFilter.contains { $0.rawValue == presentation.stateRaw }
            },
            sortBy: [SortDescriptor(\.presentedAt, order: .reverse)]
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("⚠️ [findPresentationsNeedingFollowUp] Failed to fetch: \(error)")
            return []
        }
    }
    
    /// Checks if a presentation already has work generated for it
    /// - Parameters:
    ///   - presentation: The presentation to check
    ///   - context: SwiftData model context
    /// - Returns: True if work items exist for this presentation
    @MainActor
    static func hasGeneratedWork(
        for presentation: Presentation,
        in context: ModelContext
    ) -> Bool {
        let relatedWork = presentation.fetchRelatedWork(from: context)
        return !relatedWork.isEmpty
    }
    
    /// Suggests work based on presentation analysis and existing work
    /// - Parameters:
    ///   - presentation: The presentation to analyze
    ///   - context: SwiftData model context
    /// - Returns: Suggested work items (not yet created in database)
    @MainActor
    static func suggestWork(
        for presentation: Presentation,
        in context: ModelContext
    ) -> [WorkSuggestion] {
        var suggestions: [WorkSuggestion] = []
        
        guard let lesson = presentation.lesson else {
            return suggestions
        }
        
        let existingWork = presentation.fetchRelatedWork(from: context)
        let existingKinds = Set(existingWork.compactMap { $0.kind })
        
        // Suggest practice work if needed and not already created
        if presentation.needsPractice && !existingKinds.contains(.practiceLesson) {
            for studentID in presentation.studentUUIDs {
                suggestions.append(WorkSuggestion(
                    title: "Practice: \(lesson.name)",
                    kind: .practiceLesson,
                    studentID: studentID,
                    reason: "Presentation marked as needing practice"
                ))
            }
        }
        
        // Suggest follow-up work if specified and not already created
        if !presentation.followUpWork.isEmpty && !existingKinds.contains(.followUpAssignment) {
            for studentID in presentation.studentUUIDs {
                suggestions.append(WorkSuggestion(
                    title: presentation.followUpWork,
                    kind: .followUpAssignment,
                    studentID: studentID,
                    reason: "Follow-up work specified in presentation"
                ))
            }
        }
        
        return suggestions
    }
}

// MARK: - Supporting Types

/// Represents the follow-up actions needed for a presentation
struct PresentationFollowUp {
    let presentationID: UUID
    let actions: [FollowUpAction]
    let priority: FollowUpPriority
    let notes: String
    
    var hasActions: Bool {
        !actions.isEmpty
    }
}

/// Specific follow-up actions that can be taken
enum FollowUpAction: Equatable {
    case createPracticeWork
    case createFollowUpWork(description: String)
    case scheduleRepresentation
    
    var description: String {
        switch self {
        case .createPracticeWork:
            return "Create practice work items"
        case .createFollowUpWork(let desc):
            return "Create follow-up work: \(desc)"
        case .scheduleRepresentation:
            return "Schedule another presentation"
        }
    }
    
    var icon: String {
        switch self {
        case .createPracticeWork:
            return "pencil.circle"
        case .createFollowUpWork:
            return "arrow.uturn.forward.circle"
        case .scheduleRepresentation:
            return "calendar.badge.plus"
        }
    }
}

/// Priority levels for follow-up actions
enum FollowUpPriority: Int, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    
    static func < (lhs: FollowUpPriority, rhs: FollowUpPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var label: String {
        switch self {
        case .none: return "No Action Needed"
        case .low: return "Low Priority"
        case .medium: return "Medium Priority"
        case .high: return "High Priority"
        }
    }
    
    var color: String {
        switch self {
        case .none: return "gray"
        case .low: return "blue"
        case .medium: return "orange"
        case .high: return "red"
        }
    }
}

/// A suggested work item (not yet created in database)
struct WorkSuggestion {
    let title: String
    let kind: WorkKind
    let studentID: UUID
    let reason: String
    
    /// Creates a WorkModel from this suggestion
    func createWorkModel(
        lessonID: String,
        presentationID: String
    ) -> WorkModel {
        WorkModel(
            title: title,
            kind: kind,
            status: .active,
            studentID: studentID.uuidString,
            lessonID: lessonID,
            presentationID: presentationID
        )
    }
}

// MARK: - Convenience Extensions

extension Presentation {
    /// Generates and saves follow-up work for this presentation
    @MainActor
    func generateFollowUpWork(in context: ModelContext) -> [WorkModel] {
        FollowUpWorkService.generateWorkFromPresentation(self, context: context)
    }
    
    /// Analyzes this presentation for follow-up needs
    nonisolated func analyzeFollowUp() -> PresentationFollowUp {
        FollowUpWorkService.analyzePresentation(self)
    }
    
    /// Gets suggested work items (not yet created)
    @MainActor
    func getSuggestedWork(from context: ModelContext) -> [WorkSuggestion] {
        FollowUpWorkService.suggestWork(for: self, in: context)
    }
}
