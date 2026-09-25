// CDWorkStepServiceImpl.swift
// Thin wrapper that forwards work-step edits to WorkStepService.

import Foundation
import CoreData

final class CDWorkStepServiceImpl {
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

    func toggleCompletion(_ step: CDWorkStep, at date: Date = Date()) throws {
        try cdService.toggleCompletion(step, at: date)
    }

    // MARK: - Deletion

    func delete(_ step: CDWorkStep, from work: CDWorkModel? = nil) throws {
        try cdService.delete(step, from: work)
    }
}
