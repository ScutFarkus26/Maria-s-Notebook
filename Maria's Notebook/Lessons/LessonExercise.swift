import Foundation
import SwiftData

/// Represents a single exercise within a Lesson (e.g., "Exercise 1: Commutative Law").
/// Exercises are ordered by orderIndex to ensure deterministic sequencing.
/// Follows the WorkStep child-entity pattern for CloudKit compatibility.
@Model
final class LessonExercise: Identifiable {
    /// Stable identifier
    var id: UUID = UUID()

    /// The lesson this exercise belongs to (inverse defined on Lesson.exercises)
    var lesson: Lesson? = nil

    /// Order index within the lesson (0-based, lower numbers come first)
    var orderIndex: Int = 0

    /// Exercise title (e.g., "Exercise 1: Commutative Law of Multiplication")
    var title: String = ""

    /// Preparation steps or prerequisites for this exercise
    var preparation: String = ""

    /// Newline-separated presentation steps for the teacher to follow
    var presentationSteps: String = ""

    /// Additional notes specific to this exercise
    var notes: String = ""

    /// Creation timestamp
    var createdAt: Date = Date()

    // MARK: - Computed Helpers

    /// Parse presentationSteps into an ordered array
    @Transient
    var presentationStepItems: [String] {
        presentationSteps
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        lesson: Lesson? = nil,
        orderIndex: Int = 0,
        title: String = "",
        preparation: String = "",
        presentationSteps: String = "",
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.lesson = lesson
        self.orderIndex = orderIndex
        self.title = title
        self.preparation = preparation
        self.presentationSteps = presentationSteps
        self.notes = notes
        self.createdAt = createdAt
    }
}
