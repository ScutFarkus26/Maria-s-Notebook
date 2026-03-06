import Foundation
import SwiftData
import SwiftUI

/// WorkStep model representing a single step in a Report-type WorkModel.
/// Steps are ordered by orderIndex to ensure deterministic progression.
@Model
final class WorkStep: Identifiable {
    /// Stable identifier
    var id: UUID = UUID()

    /// The work this step belongs to (relationship defined on WorkModel.steps)
    var work: WorkModel?

    /// Order index within the work (0-based, lower numbers come first)
    var orderIndex: Int = 0

    /// Step title/name
    var title: String = ""

    /// Detailed instructions for this step
    var instructions: String = ""

    /// When this step was completed (nil if not yet completed)
    var completedAt: Date?

    /// Notes about this step
    var notes: String = ""

    /// Completion outcome for this step (mastered, needsMorePractice, etc.)
    var completionOutcomeRaw: String?

    /// Creation timestamp
    var createdAt: Date = Date()

    /// Computed convenience for completion check
    var isCompleted: Bool { completedAt != nil }

    /// Completion outcome (reuses CompletionOutcome enum from WorkTypes)
    var completionOutcome: CompletionOutcome? {
        get { completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0) } }
        set { completionOutcomeRaw = newValue?.rawValue }
    }

    // MARK: - Styling

    /// Icon name based on completion status and outcome
    var iconName: String {
        guard isCompleted else { return "circle" }
        if let outcome = completionOutcome {
            return outcome.iconName
        }
        return "checkmark.circle.fill"
    }

    /// Color based on completion status and outcome
    var statusColor: Color {
        guard isCompleted else { return .secondary }
        if let outcome = completionOutcome {
            return outcome.color
        }
        return .green
    }

    init(
        id: UUID = UUID(),
        work: WorkModel? = nil,
        orderIndex: Int = 0,
        title: String = "",
        instructions: String = "",
        completedAt: Date? = nil,
        notes: String = "",
        completionOutcomeRaw: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.work = work
        self.orderIndex = orderIndex
        self.title = title
        self.instructions = instructions
        // Use Calendar.current to avoid MainActor constraints
        let cal = Calendar.current
        self.completedAt = completedAt.map { cal.startOfDay(for: $0) }
        self.notes = notes
        self.completionOutcomeRaw = completionOutcomeRaw
        self.createdAt = createdAt
    }
}
