// SampleWorkService.swift
// Persistence service for CDSampleWorkEntity and SampleWorkStep CRUD operations.

import Foundation
import CoreData

/// Centralizes persistence for CDSampleWorkEntity and CDSampleWorkStepEntity operations.
/// Follows the WorkStepService pattern: model methods remain side-effect free,
/// callers perform explicit, transactional operations that throw on failure.
@MainActor
struct SampleWorkService {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // Deprecated ModelContext init removed - no longer needed with Core Data.

    // MARK: - CDSampleWorkEntity CRUD

    /// Create and insert a new sample work for the given lesson.
    /// - Returns: The newly created CDSampleWorkEntity with auto-incremented orderIndex.
    @discardableResult
    func createSampleWork(
        for lesson: CDLesson,
        title: String,
        workKind: WorkKind = .practiceLesson,
        notes: String = ""
    ) -> CDSampleWorkEntity {
        let existing = lesson.orderedSampleWorks
        let nextIndex = existing.isEmpty ? 0 : (existing.map { Int($0.orderIndex) }.max() ?? -1) + 1

        let sampleWork = CDSampleWorkEntity(context: context)
        sampleWork.lesson = lesson
        sampleWork.title = title.trimmed()
        sampleWork.workKind = workKind
        sampleWork.orderIndex = Int64(nextIndex)
        sampleWork.notes = notes.trimmed()
        lesson.addToSampleWorks(sampleWork)

        return sampleWork
    }

    /// Update sample work content.
    func update(_ sampleWork: CDSampleWorkEntity, title: String, workKind: WorkKind, notes: String) {
        sampleWork.title = title.trimmed()
        sampleWork.workKind = workKind
        sampleWork.notes = notes.trimmed()
    }

    /// Reorder sample works after drag operation. Updates orderIndex values based on array position.
    func reorder(_ sampleWorks: [CDSampleWorkEntity]) {
        for (index, sw) in sampleWorks.enumerated() {
            sw.orderIndex = Int64(index)
        }
    }

    /// Delete a sample work and its steps (cascade).
    func delete(_ sampleWork: CDSampleWorkEntity) {
        context.delete(sampleWork)
    }

    // MARK: - SampleWorkStep CRUD

    /// Create and insert a new step for the given sample work.
    /// - Returns: The newly created CDSampleWorkStepEntity with auto-incremented orderIndex.
    @discardableResult
    func createStep(
        for sampleWork: CDSampleWorkEntity,
        title: String,
        instructions: String = ""
    ) -> CDSampleWorkStepEntity {
        let existing = sampleWork.orderedSteps
        let nextIndex = existing.isEmpty ? 0 : (existing.map { Int($0.orderIndex) }.max() ?? -1) + 1

        let step = CDSampleWorkStepEntity(context: context)
        step.sampleWork = sampleWork
        step.title = title.trimmed()
        step.orderIndex = Int64(nextIndex)
        step.instructions = instructions.trimmed()

        return step
    }

    /// Update step content.
    func updateStep(_ step: CDSampleWorkStepEntity, title: String, instructions: String) {
        step.title = title.trimmed()
        step.instructions = instructions.trimmed()
    }

    /// Reorder steps after drag operation.
    func reorderSteps(_ steps: [CDSampleWorkStepEntity]) {
        for (index, step) in steps.enumerated() {
            step.orderIndex = Int64(index)
        }
    }

    /// Delete a step.
    func deleteStep(_ step: CDSampleWorkStepEntity) {
        context.delete(step)
    }

    // Deprecated SwiftData bridge overloads removed - typealiases now point to CD types directly.

    // MARK: - Instantiation

    /// Copies template steps from a CDSampleWorkEntity into CDWorkSteps on a CDWorkModel.
    /// Sets the work's sampleWorkID for traceability.
    func instantiate(
        sampleWork: CDSampleWorkEntity,
        into work: CDWorkModel,
        stepService: WorkStepService
    ) throws {
        work.sampleWorkID = sampleWork.id?.uuidString
        for templateStep in sampleWork.orderedSteps {
            try stepService.createStep(
                for: work,
                title: templateStep.title,
                instructions: templateStep.instructions
            )
        }
    }
}
