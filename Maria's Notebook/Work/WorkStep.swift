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
    var work: WorkModel? = nil

    /// Order index within the work (0-based, lower numbers come first)
    var orderIndex: Int = 0

    /// Step title/name
    var title: String = ""

    /// Detailed instructions for this step
    var instructions: String = ""

    /// When this step was completed (nil if not yet completed)
    var completedAt: Date? = nil

    /// Notes about this step
    var notes: String = ""

    /// Creation timestamp
    var createdAt: Date = Date()

    /// Computed convenience for completion check
    var isCompleted: Bool { completedAt != nil }

    // MARK: - Styling

    /// Icon name based on completion status
    var iconName: String {
        isCompleted ? "checkmark.circle.fill" : "circle"
    }

    /// Color based on completion status
    var statusColor: Color {
        isCompleted ? .green : .secondary
    }

    init(
        id: UUID = UUID(),
        work: WorkModel? = nil,
        orderIndex: Int = 0,
        title: String = "",
        instructions: String = "",
        completedAt: Date? = nil,
        notes: String = "",
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
        self.createdAt = createdAt
    }
}
