//
//  WorkStepServiceProtocol.swift
//  Maria's Notebook
//
//  Created by Architecture Migration - Phase 1
//  Protocol-based service architecture for WorkStepService
//

import Foundation
import SwiftData

// MARK: - Protocol Definition

/// Protocol for WorkStep operations
/// Defines the interface for creating, updating, and deleting work steps
protocol WorkStepServiceProtocol {
    var context: ModelContext { get }
    
    // MARK: - Creation
    
    /// Create and insert a new step for the given work
    /// - Parameters:
    ///   - work: The work item to create a step for
    ///   - title: The step title
    ///   - instructions: Step instructions (optional)
    ///   - notes: Additional notes (optional)
    /// - Returns: The newly created WorkStep with auto-incremented orderIndex
    /// - Throws: SwiftData persistence errors
    @discardableResult
    func createStep(for work: WorkModel, title: String, instructions: String, notes: String) throws -> WorkStep
    
    // MARK: - Updates
    
    /// Update step content
    /// - Parameters:
    ///   - step: The step to update
    ///   - title: New title
    ///   - instructions: New instructions
    ///   - notes: New notes
    /// - Throws: SwiftData persistence errors
    func update(_ step: WorkStep, title: String, instructions: String, notes: String) throws
    
    /// Mark step as completed
    /// - Parameters:
    ///   - step: The step to mark as completed
    ///   - date: The completion date (default: now)
    /// - Throws: SwiftData persistence errors
    func markCompleted(_ step: WorkStep, at date: Date) throws
    
    /// Mark step as incomplete
    /// - Parameter step: The step to mark as incomplete
    /// - Throws: SwiftData persistence errors
    func markIncomplete(_ step: WorkStep) throws
    
    /// Toggle step completion status
    /// - Parameters:
    ///   - step: The step to toggle
    ///   - date: The completion date if marking complete (default: now)
    /// - Throws: SwiftData persistence errors
    func toggleCompletion(_ step: WorkStep, at date: Date) throws
    
    /// Reorder steps after drag operation
    /// Updates orderIndex values based on array position
    /// - Parameter steps: The steps in their new order
    /// - Throws: SwiftData persistence errors
    func reorderSteps(_ steps: [WorkStep]) throws
    
    // MARK: - Deletion
    
    /// Delete a step
    /// - Parameters:
    ///   - step: The step to delete
    ///   - work: Optional work item to update relationships
    /// - Throws: SwiftData persistence errors
    func delete(_ step: WorkStep, from work: WorkModel?) throws
}

// MARK: - Adapter Implementation

/// Adapter that wraps the existing WorkStepService struct
/// Provides protocol-based interface for dependency injection and testing
final class WorkStepServiceAdapter: WorkStepServiceProtocol {
    let context: ModelContext
    private let legacyService: WorkStepService
    
    init(context: ModelContext) {
        self.context = context
        self.legacyService = WorkStepService(context: context)
    }
    
    // MARK: - Creation
    
    @discardableResult
    func createStep(
        for work: WorkModel, title: String,
        instructions: String = "", notes: String = ""
    ) throws -> WorkStep {
        try legacyService.createStep(
            for: work, title: title,
            instructions: instructions, notes: notes
        )
    }
    
    // MARK: - Updates
    
    func update(_ step: WorkStep, title: String, instructions: String, notes: String) throws {
        try legacyService.update(step, title: title, instructions: instructions, notes: notes)
    }
    
    func markCompleted(_ step: WorkStep, at date: Date = Date()) throws {
        try legacyService.markCompleted(step, at: date)
    }
    
    func markIncomplete(_ step: WorkStep) throws {
        try legacyService.markIncomplete(step)
    }
    
    func toggleCompletion(_ step: WorkStep, at date: Date = Date()) throws {
        try legacyService.toggleCompletion(step, at: date)
    }
    
    func reorderSteps(_ steps: [WorkStep]) throws {
        try legacyService.reorderSteps(steps)
    }
    
    // MARK: - Deletion
    
    func delete(_ step: WorkStep, from work: WorkModel? = nil) throws {
        try legacyService.delete(step, from: work)
    }
}

// MARK: - Mock for Testing

#if DEBUG
/// Mock implementation for testing
/// Provides in-memory implementation without actual persistence
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
