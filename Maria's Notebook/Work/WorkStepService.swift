// WorkStepService.swift
// Small persistence service for WorkStep operations to keep model methods side-effect free.

import Foundation
import SwiftData

/// A small service that centralizes persistence for WorkStep operations.
///
/// This service ensures that model methods remain free of side-effects
/// (no implicit saves), while callers can perform explicit, transactional
/// operations that throw on failure.
struct WorkStepService {
    let context: ModelContext

    // MARK: - Creation

    /// Create and insert a new step for the given work.
    /// - Returns: The newly created WorkStep with auto-incremented orderIndex.
    @discardableResult
    func createStep(for work: WorkModel,
                    title: String,
                    instructions: String = "",
                    notes: String = "") throws -> WorkStep {
        let existingSteps = work.steps ?? []
        let nextIndex = existingSteps.isEmpty ? 0 : (existingSteps.map { $0.orderIndex }.max() ?? -1) + 1

        let step = WorkStep(
            work: work,
            orderIndex: nextIndex,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(step)

        if work.steps == nil { work.steps = [] }
        work.steps = (work.steps ?? []) + [step]

        return step
    }

    // MARK: - Updates

    /// Update step content.
    func update(_ step: WorkStep, title: String, instructions: String, notes: String) throws {
        step.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        step.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        step.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mark step as completed.
    func markCompleted(_ step: WorkStep, at date: Date = Date()) throws {
        let cal = Calendar.current
        step.completedAt = cal.startOfDay(for: date)
    }

    /// Mark step as incomplete.
    func markIncomplete(_ step: WorkStep) throws {
        step.completedAt = nil
    }

    /// Toggle step completion.
    func toggleCompletion(_ step: WorkStep, at date: Date = Date()) throws {
        if step.completedAt != nil {
            step.completedAt = nil
        } else {
            let cal = Calendar.current
            step.completedAt = cal.startOfDay(for: date)
        }
    }

    /// Reorder steps after drag operation. Updates orderIndex values based on array position.
    func reorderSteps(_ steps: [WorkStep]) throws {
        for (index, step) in steps.enumerated() {
            step.orderIndex = index
        }
    }

    // MARK: - Deletion

    /// Delete a step from its context.
    func delete(_ step: WorkStep, from work: WorkModel? = nil) throws {
        if let work = work {
            if var list = work.steps {
                list.removeAll { $0.id == step.id }
                work.steps = list
            }
        }
        context.delete(step)
    }
}
