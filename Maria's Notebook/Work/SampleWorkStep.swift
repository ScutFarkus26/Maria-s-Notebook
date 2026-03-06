import Foundation
import SwiftData

/// Represents a single step in a SampleWork template.
/// For example, "Set 1", "Set 2", etc. in a Word Study drawer.
///
/// This is a lightweight template — no completion tracking or mastery.
/// When the template is instantiated, each SampleWorkStep creates a WorkStep
/// on the resulting WorkModel, where per-student progress tracking lives.
@Model
final class SampleWorkStep: Identifiable {
    /// Stable identifier
    var id: UUID = UUID()

    /// The sample work this step belongs to (inverse defined on SampleWork.steps)
    var sampleWork: SampleWork?

    /// Step title (e.g., "Set 1", "Activity A")
    var title: String = ""

    /// Order index within the sample work (0-based, lower numbers come first)
    var orderIndex: Int = 0

    /// Optional guidance or instructions for this step
    var instructions: String = ""

    /// Creation timestamp
    var createdAt: Date = Date()

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        sampleWork: SampleWork? = nil,
        title: String = "",
        orderIndex: Int = 0,
        instructions: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sampleWork = sampleWork
        self.title = title
        self.orderIndex = orderIndex
        self.instructions = instructions
        self.createdAt = createdAt
    }
}
