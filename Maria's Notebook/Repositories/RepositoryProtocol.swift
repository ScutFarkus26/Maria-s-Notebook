//
//  RepositoryProtocol.swift
//  Maria's Notebook
//
//  Base protocol defining common CRUD patterns for repositories.
//  Enables mock implementations for testing.
//

import Foundation
import SwiftData

/// Protocol defining standard repository operations.
/// Repositories encapsulate data access, making views testable without a real database.
@MainActor
protocol Repository {
    associatedtype Model: PersistentModel

    /// The ModelContext used for data operations
    var context: ModelContext { get }
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
        do {
            try context.save()
            return true
        } catch {
            return false
        }
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
        do {
            try context.save()
            ToastService.shared.showSuccess(successMessage)
            return true
        } catch {
            return false
        }
    }
}
