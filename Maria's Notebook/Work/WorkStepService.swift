// WorkStepService.swift
// Small persistence service for WorkStep operations to keep model methods side-effect free.

import Foundation
import CoreData

/// A small service that centralizes persistence for WorkStep operations.
///
/// This service ensures that model methods remain free of side-effects
/// (no implicit saves), while callers can perform explicit, transactional
/// operations that throw on failure.
struct WorkStepService: WorkStepServiceProtocol {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // Deprecated ModelContext init removed - no longer needed with Core Data.

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

    /// Mark step as completed.
    func markCompleted(_ step: CDWorkStep, at date: Date = Date()) throws {
        let cal = Calendar.current
        step.completedAt = cal.startOfDay(for: date)
    }

    /// Mark step as incomplete.
    func markIncomplete(_ step: CDWorkStep) throws {
        step.completedAt = nil
    }

    /// Toggle step completion.
    func toggleCompletion(_ step: CDWorkStep, at date: Date = Date()) throws {
        if step.completedAt != nil {
            step.completedAt = nil
        } else {
            let cal = Calendar.current
            step.completedAt = cal.startOfDay(for: date)
        }
    }

    /// Reorder steps after drag operation. Updates orderIndex values based on array position.
    func reorderSteps(_ steps: [CDWorkStep]) throws {
        for (index, step) in steps.enumerated() {
            step.orderIndex = Int64(index)
        }
    }

    // MARK: - Deletion

    /// Delete a step from its context.
    func delete(_ step: CDWorkStep, from work: CDWorkModel? = nil) throws {
        if let work {
            work.removeFromSteps(step)
        }
        context.delete(step)
    }
}
