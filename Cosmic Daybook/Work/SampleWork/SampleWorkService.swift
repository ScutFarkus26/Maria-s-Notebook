// SampleWorkService.swift
// Persistence service for CDSampleWork and SampleWorkStep CRUD operations.

import Foundation
import CoreData

/// Centralizes persistence for CDSampleWork and CDSampleWorkStep operations.
/// Follows the WorkStepService pattern: model methods remain side-effect free,
/// callers perform explicit, transactional operations that throw on failure.
struct SampleWorkService {
    let context: NSManagedObjectContext

    // MARK: - CDSampleWork CRUD

    /// Create and insert a new sample work for the given lesson.
    /// - Returns: The newly created CDSampleWork with auto-incremented orderIndex.
    @discardableResult
    func createSampleWork(
        for lesson: CDLesson,
        title: String,
        workKind: WorkKind = .practiceLesson,
        notes: String = ""
    ) -> CDSampleWork {
        let existing = lesson.orderedSampleWorks
        let nextIndex = existing.isEmpty ? 0 : (existing.map { Int($0.orderIndex) }.max() ?? -1) + 1

        let sampleWork = CDSampleWork(context: context)
        sampleWork.lesson = lesson
        sampleWork.title = title.trimmed()
        sampleWork.workKind = workKind
        sampleWork.orderIndex = Int64(nextIndex)
        sampleWork.notes = notes.trimmed()
        lesson.addToSampleWorks(sampleWork)

        return sampleWork
    }

    /// Update sample work content.
    func update(_ sampleWork: CDSampleWork, title: String, workKind: WorkKind, notes: String) {
        sampleWork.title = title.trimmed()
        sampleWork.workKind = workKind
        sampleWork.notes = notes.trimmed()
    }

    /// Delete a sample work and its steps (cascade).
    func delete(_ sampleWork: CDSampleWork) {
        context.delete(sampleWork)
    }

    // MARK: - SampleWorkStep CRUD

    /// Create and insert a new step for the given sample work.
    /// - Returns: The newly created CDSampleWorkStep with auto-incremented orderIndex.
    @discardableResult
    func createStep(
        for sampleWork: CDSampleWork,
        title: String,
        instructions: String = ""
    ) -> CDSampleWorkStep {
        let existing = sampleWork.orderedSteps
        let nextIndex = existing.isEmpty ? 0 : (existing.map { Int($0.orderIndex) }.max() ?? -1) + 1

        let step = CDSampleWorkStep(context: context)
        step.sampleWork = sampleWork
        step.title = title.trimmed()
        step.orderIndex = Int64(nextIndex)
        step.instructions = instructions.trimmed()

        return step
    }

    /// Update step content.
    func updateStep(_ step: CDSampleWorkStep, title: String, instructions: String) {
        step.title = title.trimmed()
        step.instructions = instructions.trimmed()
    }

    /// Delete a step.
    func deleteStep(_ step: CDSampleWorkStep) {
        context.delete(step)
    }

    // MARK: - Instantiation

    /// Copies template steps from a CDSampleWork into CDWorkSteps on a CDWorkModel.
    /// Sets the work's sampleWorkID for traceability.
    func instantiate(
        sampleWork: CDSampleWork,
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
