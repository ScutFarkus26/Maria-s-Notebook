//
//  WorkStepServiceProtocol.swift
//  Maria's Notebook
//
//  Created by Architecture Migration - Phase 1
//  Protocol-based service architecture for WorkStepService
//

import Foundation
import CoreData

// MARK: - Protocol Definition

/// Protocol for CDWorkStep operations
/// Defines the interface for creating, updating, and deleting work steps
protocol WorkStepServiceProtocol {
    var context: NSManagedObjectContext { get }

    // MARK: - Creation

    /// Create and insert a new step for the given work
    @discardableResult
    func createStep(for work: CDWorkModel, title: String, instructions: String, notes: String) throws -> CDWorkStep

    // MARK: - Updates

    func update(_ step: CDWorkStep, title: String, instructions: String, notes: String) throws
    func markCompleted(_ step: CDWorkStep, at date: Date) throws
    func markIncomplete(_ step: CDWorkStep) throws
    func toggleCompletion(_ step: CDWorkStep, at date: Date) throws
    func reorderSteps(_ steps: [CDWorkStep]) throws

    // MARK: - Deletion

    func delete(_ step: CDWorkStep, from work: CDWorkModel?) throws
}

// MARK: - Concrete Implementation

/// Concrete implementation that delegates to WorkStepService.
/// Now works directly with Core Data types (no adapter bridging needed).
final class CDWorkStepServiceImpl: WorkStepServiceProtocol {
    let context: NSManagedObjectContext
    private let cdService: WorkStepService

    @MainActor
    init(context: NSManagedObjectContext) {
        self.context = context
        self.cdService = WorkStepService(context: context)
    }

    // MARK: - Creation

    @discardableResult
    func createStep(
        for work: CDWorkModel, title: String,
        instructions: String = "", notes: String = ""
    ) throws -> CDWorkStep {
        try cdService.createStep(for: work, title: title, instructions: instructions, notes: notes)
    }

    // MARK: - Updates

    func update(_ step: CDWorkStep, title: String, instructions: String, notes: String) throws {
        try cdService.update(step, title: title, instructions: instructions, notes: notes)
    }

    func markCompleted(_ step: CDWorkStep, at date: Date = Date()) throws {
        try cdService.markCompleted(step, at: date)
    }

    func markIncomplete(_ step: CDWorkStep) throws {
        try cdService.markIncomplete(step)
    }

    func toggleCompletion(_ step: CDWorkStep, at date: Date = Date()) throws {
        try cdService.toggleCompletion(step, at: date)
    }

    func reorderSteps(_ steps: [CDWorkStep]) throws {
        try cdService.reorderSteps(steps)
    }

    // MARK: - Deletion

    func delete(_ step: CDWorkStep, from work: CDWorkModel? = nil) throws {
        try cdService.delete(step, from: work)
    }
}

// MARK: - Mock for Testing

#if DEBUG
/// Mock implementation for testing
final class MockWorkStepService: WorkStepServiceProtocol {
    let context: NSManagedObjectContext
    var createdSteps: [CDWorkStep] = []
    var deletedStepIDs: [UUID] = []
    var completedStepIDs: [UUID] = []
    var reorderedSteps: [[CDWorkStep]] = []

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func createStep(
        for work: CDWorkModel, title: String,
        instructions: String = "", notes: String = ""
    ) throws -> CDWorkStep {
        let step = CDWorkStep(context: context)
        step.id = UUID()
        step.work = work
        step.orderIndex = Int64(createdSteps.count)
        step.title = title
        step.instructions = instructions
        step.notes = notes
        createdSteps.append(step)
        return step
    }

    func update(_ step: CDWorkStep, title: String, instructions: String, notes: String) throws {
        step.title = title
        step.instructions = instructions
        step.notes = notes
    }

    func markCompleted(_ step: CDWorkStep, at date: Date = Date()) throws {
        if let id = step.id { completedStepIDs.append(id) }
        step.completedAt = date
    }

    func markIncomplete(_ step: CDWorkStep) throws {
        step.completedAt = nil
    }

    func toggleCompletion(_ step: CDWorkStep, at date: Date = Date()) throws {
        if step.completedAt != nil {
            step.completedAt = nil
        } else {
            step.completedAt = date
            if let id = step.id { completedStepIDs.append(id) }
        }
    }

    func reorderSteps(_ steps: [CDWorkStep]) throws {
        reorderedSteps.append(steps)
        for (index, step) in steps.enumerated() {
            step.orderIndex = Int64(index)
        }
    }

    func delete(_ step: CDWorkStep, from work: CDWorkModel? = nil) throws {
        if let id = step.id { deletedStepIDs.append(id) }
    }
}
#endif
