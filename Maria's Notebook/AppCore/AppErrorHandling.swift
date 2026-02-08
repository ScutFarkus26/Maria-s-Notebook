//
//  AppErrorHandling.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import Foundation

/// Centralized error handling for database and app initialization failures.
final class AppErrorHandling {
    
    // MARK: - Error Handling
    
    /// Centralized error handling for database initialization failures.
    /// Delegates to DatabaseInitializationService.
    @MainActor
    static func handleDatabaseInitError(_ error: Error, description: String? = nil) {
        DatabaseInitializationService.handleDatabaseInitError(error, description: description)
    }

    /// Handles critical database initialization failure with multiple error contexts.
    /// Delegates to DatabaseInitializationService.
    @MainActor
    static func handleCriticalDatabaseInitError(
        originalError: Error,
        finalError: Error? = nil,
        emptyContainerError: Error? = nil,
        errorCode: Int = 5002
    ) {
        DatabaseInitializationService.handleCriticalDatabaseInitError(
            originalError: originalError,
            finalError: finalError,
            emptyContainerError: emptyContainerError,
            errorCode: errorCode
        )
    }
}
