//
//  WorkStepServiceProtocol.swift
//  Maria's Notebook
//
//  Created by Architecture Migration - Phase 1
//  Protocol-based service architecture for WorkStepService
//

import Foundation
import SwiftData
import CoreData

// MARK: - Protocol Definition

/// Protocol for WorkStep operations
/// Defines the interface for creating, updating, and deleting work steps
protocol WorkStepServiceProtocol {
    var context: ModelContext { get }

    // MARK: - Creation

    /// Create and insert a new step for the given work
    @discardableResult
    func createStep(for work: WorkModel, title: String, instructions: String, notes: String) throws -> WorkStep

    // MARK: - Updates

    func update(_ step: WorkStep, title: String, instructions: String, notes: String) throws
    func markCompleted(_ step: WorkStep, at date: Date) throws
    func markIncomplete(_ step: WorkStep) throws
    func toggleCompletion(_ step: WorkStep, at date: Date) throws
    func reorderSteps(_ steps: [WorkStep]) throws

    // MARK: - Deletion

    func delete(_ step: WorkStep, from work: WorkModel?) throws
}

// MARK: - Adapter Implementation

/// Adapter that wraps the existing WorkStepService struct.
/// Bridges SwiftData types to Core Data internally during the transition.
final class WorkStepServiceAdapter: WorkStepServiceProtocol {
    let context: ModelContext
    private let cdService: WorkStepService
    private let cdContext: NSManagedObjectContext

    @MainActor
    init(context: ModelContext) {
        self.context = context
        self.cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        self.cdService = WorkStepService(context: cdContext)
    }

    // MARK: - CD Lookup Helpers

    private func cdWork(for work: WorkModel) -> CDWorkModel? {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", work.id as CVarArg)
        request.fetchLimit = 1
        return cdContext.safeFetchFirst(request)
    }

    private func cdStep(for step: WorkStep) -> CDWorkStep? {
        let request = CDFetchRequest(CDWorkStep.self)
        request.predicate = NSPredicate(format: "id == %@", step.id as CVarArg)
        request.fetchLimit = 1
        return cdContext.safeFetchFirst(request)
    }

    // MARK: - Creation

    @discardableResult
    func createStep(
        for work: WorkModel, title: String,
        instructions: String = "", notes: String = ""
    ) throws -> WorkStep {
        guard let cdW = cdWork(for: work) else {
            throw NSError(domain: "WorkStepServiceAdapter", code: 1, userInfo: [NSLocalizedDescriptionKey: "CDWorkModel not found"])
        }
        let cdStep = try cdService.createStep(for: cdW, title: title, instructions: instructions, notes: notes)
        // Return SwiftData WorkStep for protocol conformance
        let swiftDataStep = WorkStep(
            work: work, orderIndex: Int(cdStep.orderIndex),
            title: title, instructions: instructions, notes: notes
        )
        swiftDataStep.id = cdStep.id ?? UUID()
        context.insert(swiftDataStep)
        return swiftDataStep
    }

    // MARK: - Updates

    func update(_ step: WorkStep, title: String, instructions: String, notes: String) throws {
        guard let cdS = cdStep(for: step) else { return }
        try cdService.update(cdS, title: title, instructions: instructions, notes: notes)
    }

    func markCompleted(_ step: WorkStep, at date: Date = Date()) throws {
        guard let cdS = cdStep(for: step) else { return }
        try cdService.markCompleted(cdS, at: date)
    }

    func markIncomplete(_ step: WorkStep) throws {
        guard let cdS = cdStep(for: step) else { return }
        try cdService.markIncomplete(cdS)
    }

    func toggleCompletion(_ step: WorkStep, at date: Date = Date()) throws {
        guard let cdS = cdStep(for: step) else { return }
        try cdService.toggleCompletion(cdS, at: date)
    }

    func reorderSteps(_ steps: [WorkStep]) throws {
        let cdSteps = steps.compactMap { cdStep(for: $0) }
        try cdService.reorderSteps(cdSteps)
    }

    // MARK: - Deletion

    func delete(_ step: WorkStep, from work: WorkModel? = nil) throws {
        guard let cdS = cdStep(for: step) else { return }
        let cdW = work.flatMap { cdWork(for: $0) }
        try cdService.delete(cdS, from: cdW)
    }
}

// MARK: - Mock for Testing

#if DEBUG
/// Mock implementation for testing
final class MockWorkStepService: WorkStepServiceProtocol {
    let context: ModelContext
    var createdSteps: [WorkStep] = []
    var deletedStepIDs: [UUID] = []
    var completedStepIDs: [UUID] = []
    var reorderedSteps: [[WorkStep]] = []

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func createStep(
        for work: WorkModel, title: String,
        instructions: String = "", notes: String = ""
    ) throws -> WorkStep {
        let step = WorkStep(
            work: work, orderIndex: createdSteps.count,
            title: title, instructions: instructions,
            notes: notes
        )
        createdSteps.append(step)
        return step
    }

    func update(_ step: WorkStep, title: String, instructions: String, notes: String) throws {
        step.title = title
        step.instructions = instructions
        step.notes = notes
    }

    func markCompleted(_ step: WorkStep, at date: Date = Date()) throws {
        completedStepIDs.append(step.id)
        step.completedAt = date
    }

    func markIncomplete(_ step: WorkStep) throws {
        step.completedAt = nil
    }

    func toggleCompletion(_ step: WorkStep, at date: Date = Date()) throws {
        if step.completedAt != nil {
            step.completedAt = nil
        } else {
            step.completedAt = date
            completedStepIDs.append(step.id)
        }
    }

    func reorderSteps(_ steps: [WorkStep]) throws {
        reorderedSteps.append(steps)
        for (index, step) in steps.enumerated() {
            step.orderIndex = index
        }
    }

    func delete(_ step: WorkStep, from work: WorkModel? = nil) throws {
        deletedStepIDs.append(step.id)
    }
}
#endif
