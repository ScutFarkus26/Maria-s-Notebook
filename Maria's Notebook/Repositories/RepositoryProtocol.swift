//
//  RepositoryProtocol.swift
//  Maria's Notebook
//
//  Base protocol defining common CRUD patterns for repositories.
//  Enables mock implementations for testing.
//

import Foundation
import CoreData

/// Protocol defining standard repository operations.
/// Repositories encapsulate data access, making views testable without a real database.
@MainActor
protocol Repository {
    associatedtype Model: NSManagedObject

    /// The NSManagedObjectContext used for data operations
    var context: NSManagedObjectContext { get }
}

/// Protocol for repositories that support coordinated saves with error handling.
@MainActor
protocol SavingRepository: Repository {
    var saveCoordinator: SaveCoordinator? { get }
}

extension SavingRepository {
    /// Save changes using SaveCoordinator if available, otherwise direct save.
    /// - Parameter reason: Optional description shown to user on failure
    /// - Returns: true if save succeeded
    @discardableResult
    func save(reason: String? = nil) -> Bool {
        if let coordinator = saveCoordinator {
            return coordinator.save(context, reason: reason)
        }
        // No coordinator (e.g. tests / detached contexts): fall back to safeSave
        // so a failure is logged loudly (.fault) instead of silently dropped.
        return context.safeSave()
    }

    /// Save changes and show a success toast.
    /// - Parameters:
    ///   - successMessage: Message to show on success
    ///   - reason: Optional description shown to user on failure
    /// - Returns: true if save succeeded
    @discardableResult
    func saveWithToast(successMessage: String, reason: String? = nil) -> Bool {
        if let coordinator = saveCoordinator {
            return coordinator.saveWithToast(context, successMessage: successMessage, reason: reason)
        }
        // No coordinator: safeSave still logs a failure loudly (.fault). Only
        // show the success toast when the save actually persisted.
        guard context.safeSave() else { return false }
        ToastService.shared.showSuccess(successMessage)
        return true
    }
}
