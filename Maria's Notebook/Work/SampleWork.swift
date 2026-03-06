import Foundation
import SwiftData

/// Represents a reusable work template defined on a Lesson.
/// For example, a "Compound Words" lesson might have a SampleWork called "Skyscraper Drawers"
/// with 10 ordered steps (Sets 1-10) that students progress through.
///
/// When a teacher assigns work, they can pick a SampleWork from the lesson's templates.
/// This creates a WorkModel + WorkSteps pre-populated from the template.
@Model
final class SampleWork: Identifiable {
    /// Stable identifier
    var id: UUID = UUID()

    /// The lesson this sample work belongs to (inverse defined on Lesson.sampleWorks)
    var lesson: Lesson?

    /// Display title (e.g., "Skyscraper Drawers", "Compound Word Cards")
    var title: String = ""

    /// Raw storage for the work kind this template produces
    var workKindRaw: String = "practiceLesson"

    /// Order index within the lesson (0-based, lower numbers come first)
    var orderIndex: Int = 0

    /// Optional notes about this work template
    var notes: String = ""

    /// Creation timestamp
    var createdAt: Date = Date()

    /// Ordered steps that define the template progression (cascade-deleted with this sample work)
    @Relationship(deleteRule: .cascade, inverse: \SampleWorkStep.sampleWork)
    var steps: [SampleWorkStep]? = []

    // MARK: - Computed Properties

    /// The work kind this template produces (reuses WorkKind enum)
    @Transient
    var workKind: WorkKind? {
        get { WorkKind(rawValue: workKindRaw) }
        set { workKindRaw = newValue?.rawValue ?? WorkKind.practiceLesson.rawValue }
    }

    /// Returns steps sorted by orderIndex for deterministic display
    var orderedSteps: [SampleWorkStep] {
        (steps ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Number of steps in this template
    var stepCount: Int {
        (steps ?? []).count
    }

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        lesson: Lesson? = nil,
        title: String = "",
        workKind: WorkKind = .practiceLesson,
        orderIndex: Int = 0,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.lesson = lesson
        self.title = title
        self.workKindRaw = workKind.rawValue
        self.orderIndex = orderIndex
        self.notes = notes
        self.createdAt = createdAt
        self.steps = []
    }
}
