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
#endif
