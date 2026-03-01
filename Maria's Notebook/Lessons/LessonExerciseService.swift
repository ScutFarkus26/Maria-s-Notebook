import Foundation
import SwiftData

/// Persistence service for LessonExercise CRUD operations.
/// Follows the WorkStep service pattern: model methods remain side-effect free,
/// callers perform explicit operations.
@MainActor
struct LessonExerciseService {
    let context: ModelContext

    // MARK: - Creation

    @discardableResult
    func createExercise(
        for lesson: Lesson,
        title: String,
        preparation: String = "",
        presentationSteps: String = "",
        notes: String = ""
    ) -> LessonExercise {
        let existingExercises = lesson.exercises ?? []
        let nextIndex = existingExercises.isEmpty
            ? 0
            : (existingExercises.map { $0.orderIndex }.max() ?? -1) + 1

        let exercise = LessonExercise(
            lesson: lesson,
            orderIndex: nextIndex,
            title: title,
            preparation: preparation,
            presentationSteps: presentationSteps,
            notes: notes
        )
        context.insert(exercise)
        return exercise
    }

    // MARK: - Updates

    func update(
        _ exercise: LessonExercise,
        title: String,
        preparation: String,
        presentationSteps: String,
        notes: String
    ) {
        exercise.title = title
        exercise.preparation = preparation
        exercise.presentationSteps = presentationSteps
        exercise.notes = notes
    }

    func reorderExercises(_ exercises: [LessonExercise]) {
        for (index, exercise) in exercises.enumerated() {
            exercise.orderIndex = index
        }
    }

    // MARK: - Deletion

    func delete(_ exercise: LessonExercise) {
        context.delete(exercise)
    }
}
