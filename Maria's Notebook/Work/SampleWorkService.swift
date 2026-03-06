// SampleWorkService.swift
// Persistence service for SampleWork and SampleWorkStep CRUD operations.

import Foundation
import SwiftData

/// Centralizes persistence for SampleWork and SampleWorkStep operations.
/// Follows the WorkStepService pattern: model methods remain side-effect free,
/// callers perform explicit, transactional operations that throw on failure.
@MainActor
struct SampleWorkService {
    let context: ModelContext

    // MARK: - SampleWork CRUD

    /// Create and insert a new sample work for the given lesson.
    /// - Returns: The newly created SampleWork with auto-incremented orderIndex.
    @discardableResult
    func createSampleWork(
        for lesson: Lesson,
        title: String,
        workKind: WorkKind = .practiceLesson,
        notes: String = ""
    ) -> SampleWork {
        let existing = lesson.sampleWorks ?? []
        let nextIndex = existing.isEmpty ? 0 : (existing.map { $0.orderIndex }.max() ?? -1) + 1

        let sampleWork = SampleWork(
            lesson: lesson,
            title: title.trimmed(),
            workKind: workKind,
            orderIndex: nextIndex,
            notes: notes.trimmed()
        )
        context.insert(sampleWork)

        if lesson.sampleWorks == nil { lesson.sampleWorks = [] }
        lesson.sampleWorks = (lesson.sampleWorks ?? []) + [sampleWork]

        return sampleWork
    }

    /// Update sample work content.
    func update(_ sampleWork: SampleWork, title: String, workKind: WorkKind, notes: String) {
        sampleWork.title = title.trimmed()
        sampleWork.workKind = workKind
        sampleWork.notes = notes.trimmed()
    }

    /// Reorder sample works after drag operation. Updates orderIndex values based on array position.
    func reorder(_ sampleWorks: [SampleWork]) {
        for (index, sw) in sampleWorks.enumerated() {
            sw.orderIndex = index
        }
    }

    /// Delete a sample work and its steps (cascade).
    func delete(_ sampleWork: SampleWork) {
        context.delete(sampleWork)
    }

    // MARK: - SampleWorkStep CRUD

    /// Create and insert a new step for the given sample work.
    /// - Returns: The newly created SampleWorkStep with auto-incremented orderIndex.
    @discardableResult
    func createStep(
        for sampleWork: SampleWork,
        title: String,
        instructions: String = ""
    ) -> SampleWorkStep {
        let existing = sampleWork.steps ?? []
        let nextIndex = existing.isEmpty ? 0 : (existing.map { $0.orderIndex }.max() ?? -1) + 1

        let step = SampleWorkStep(
            sampleWork: sampleWork,
            title: title.trimmed(),
            orderIndex: nextIndex,
            instructions: instructions.trimmed()
        )
        context.insert(step)

        if sampleWork.steps == nil { sampleWork.steps = [] }
        sampleWork.steps = (sampleWork.steps ?? []) + [step]

        return step
    }

    /// Update step content.
    func updateStep(_ step: SampleWorkStep, title: String, instructions: String) {
        step.title = title.trimmed()
        step.instructions = instructions.trimmed()
    }

    /// Reorder steps after drag operation.
    func reorderSteps(_ steps: [SampleWorkStep]) {
        for (index, step) in steps.enumerated() {
            step.orderIndex = index
        }
    }

    /// Delete a step.
    func deleteStep(_ step: SampleWorkStep) {
        context.delete(step)
    }

    // MARK: - Instantiation

    /// Copies template steps from a SampleWork into WorkSteps on a WorkModel.
    /// Sets the work's sampleWorkID for traceability.
    func instantiate(
        sampleWork: SampleWork,
        into work: WorkModel,
        stepService: WorkStepService
    ) throws {
        work.sampleWorkID = sampleWork.id.uuidString
        for templateStep in sampleWork.orderedSteps {
            try stepService.createStep(
                for: work,
                title: templateStep.title,
                instructions: templateStep.instructions
            )
        }
    }
}
