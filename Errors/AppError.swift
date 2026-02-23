//
//  AppError.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import Foundation

/// Base protocol for all domain errors in the app.
/// Provides consistent error handling, recovery strategies, and user-facing messages.
protocol AppError: LocalizedError {
    /// Unique error code for logging and analytics
    var code: String { get }
    
    /// Whether the user can potentially recover from this error
    var isRecoverable: Bool { get }
    
    /// Suggested recovery actions for the user
    var recoverySuggestion: String? { get }
    
    /// Category for analytics and logging
    var category: ErrorCategory { get }
    
    /// Severity level for logging
    var severity: ErrorSeverity { get }
}

/// Categories of errors for analytics and filtering
enum ErrorCategory: String, Codable {
    case validation      // User input validation failures
    case notFound        // Entity not found
    case conflict        // Conflict with existing data
    case permission      // Permission or authorization issues
    case database        // Database/persistence failures
    case network         // Network/sync failures
    case business        // Business rule violations
    case system          // System/framework errors
}

/// Severity levels for error logging
enum ErrorSeverity: Int, Codable {
    case debug = 0       // Development-only issues
    case info = 1        // Informational, no action needed
    case warning = 2     // Warning, may affect functionality
    case error = 3       // Error, affects functionality
    case critical = 4    // Critical, app may not function
}

/// Default implementations for AppError
extension AppError {
    var code: String {
        "\(category.rawValue).\(String(describing: self))"
    }
    
    var severity: ErrorSeverity {
        isRecoverable ? .warning : .error
    }
}

/// Generic validation error for common validation failures
struct ValidationError: AppError {
    let field: String
    let reason: String
    let value: Any?
    
    var category: ErrorCategory { .validation }
    var isRecoverable: Bool { true }
    
    var errorDescription: String? {
        "Invalid \(field): \(reason)"
    }
    
    var recoverySuggestion: String? {
        "Please check the \(field) field and try again."
    }
}

/// Generic database error wrapper
struct DatabaseError: AppError {
    let operation: String
    let entity: String?
    let underlying: Error?
    
    var category: ErrorCategory { .database }
    var isRecoverable: Bool { false }
    var severity: ErrorSeverity { .critical }
    
    var errorDescription: String? {
        if let entity = entity {
            return "Database error during \(operation) for \(entity)."
        }
        return "Database error during \(operation)."
    }
    
    var recoverySuggestion: String? {
        "Please try again. If the problem persists, restart the app or contact support."
    }
    
    var failureReason: String? {
        underlying?.localizedDescription
    }
}
