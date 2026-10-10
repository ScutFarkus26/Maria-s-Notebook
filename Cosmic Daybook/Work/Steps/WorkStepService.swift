// WorkStepService.swift
// Small persistence service for CDWorkStep operations to keep model methods side-effect free.

import Foundation
import CoreData

/// A small service that centralizes persistence for CDWorkStep operations.
///
/// This service ensures that model methods remain free of side-effects
/// (no implicit saves), while callers can perform explicit, transactional
/// operations that throw on failure.
struct WorkStepService {
    let context: NSManagedObjectContext

    // MARK: - Creation

    /// Create and insert a new step for the given work.
    /// - Returns: The newly created CDWorkStep with auto-incremented orderIndex.
    @discardableResult
    func createStep(for work: CDWorkModel,
                    title: String,
                    instructions: String = "",
                    notes: String = "") throws -> CDWorkStep {
        let existingSteps = work.orderedSteps
        let nextIndex = existingSteps.isEmpty ? 0 : (existingSteps.map { Int($0.orderIndex) }.max() ?? -1) + 1

        let step = CDWorkStep(context: context)
        step.work = work
        step.orderIndex = Int64(nextIndex)
        step.title = title.trimmed()
        step.instructions = instructions.trimmed()
        step.notes = notes.trimmed()
        work.addToSteps(step)

        return step
    }

    // MARK: - Updates

    /// Update step content.
    func update(_ step: CDWorkStep, title: String, instructions: String, notes: String) throws {
        step.title = title.trimmed()
        step.instructions = instructions.trimmed()
        step.notes = notes.trimmed()
    }

    /// Toggle step completion.
    func toggleCompletion(_ step: CDWorkStep, at date: Date = Date()) throws {
        if step.completedAt != nil {
            step.completedAt = nil
        } else {
            let cal = AppCalendar.shared
            step.completedAt = cal.startOfDay(for: date)
        }
    }

    // MARK: - Deletion

    /// Delete a step from its context, and close the gap it leaves in the
    /// numbering: the rows show `orderIndex + 1`, so deleting step 2 of 4 used
    /// to leave 1, 3, 4.
    func delete(_ step: CDWorkStep, from work: CDWorkModel? = nil) throws {
        let owner = work ?? step.work
        owner?.removeFromSteps(step)
        context.delete(step)
        guard let owner else { return }
        for (index, remaining) in owner.orderedSteps.enumerated() where remaining.orderIndex != Int64(index) {
            remaining.orderIndex = Int64(index)
        }
    }
}
