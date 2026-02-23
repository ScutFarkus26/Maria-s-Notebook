//
//  WorkError.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import Foundation

/// Errors related to work item management operations
enum WorkError: AppError {
    case notFound(id: UUID)
    case invalidStatus(status: String)
    case invalidParticipant(studentID: UUID)
    case cannotStartWithoutParticipants
    case cannotCompleteWithoutSteps
    case cannotCompleteWithIncompleteSteps(incompleteCount: Int)
    case stepNotFound(id: UUID)
    case checkInNotFound(id: UUID)
    case alreadyCompleted
    case alreadyCancelled
    case missingRequiredField(field: String)
    case invalidDuration(duration: TimeInterval)
    case invalidObservation(reason: String)
    
    var category: ErrorCategory {
        switch self {
        case .notFound, .stepNotFound, .checkInNotFound:
            return .notFound
        case .invalidStatus, .missingRequiredField, .invalidDuration, .invalidObservation:
            return .validation
        case .invalidParticipant, .cannotStartWithoutParticipants, .cannotCompleteWithoutSteps,
             .cannotCompleteWithIncompleteSteps, .alreadyCompleted, .alreadyCancelled:
            return .business
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .notFound, .stepNotFound, .checkInNotFound, .alreadyCompleted, .alreadyCancelled:
            return false
        case .invalidStatus, .invalidParticipant, .cannotStartWithoutParticipants,
             .cannotCompleteWithoutSteps, .cannotCompleteWithIncompleteSteps,
             .missingRequiredField, .invalidDuration, .invalidObservation:
            return true
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Work item not found"
            
        case .invalidStatus(let status):
            return "Invalid status: \(status)"
            
        case .invalidParticipant:
            return "Invalid participant"
            
        case .cannotStartWithoutParticipants:
            return "Cannot start work without participants"
            
        case .cannotCompleteWithoutSteps:
            return "Cannot complete work without steps"
            
        case .cannotCompleteWithIncompleteSteps(let count):
            return "Cannot complete work with \(count) incomplete step\(count == 1 ? "" : "s")"
            
        case .stepNotFound:
            return "Work step not found"
            
        case .checkInNotFound:
            return "Check-in not found"
            
        case .alreadyCompleted:
            return "Work already completed"
            
        case .alreadyCancelled:
            return "Work already cancelled"
            
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
            
        case .invalidDuration(let duration):
            return "Invalid duration: \(Int(duration / 60)) minutes"
            
        case .invalidObservation(let reason):
            return "Invalid observation: \(reason)"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .notFound:
            return "The work item may have been deleted or does not exist."
            
        case .invalidStatus(let status):
            return "'\(status)' is not a valid work status."
            
        case .invalidParticipant(let id):
            return "Student with ID \(id) is not enrolled or does not exist."
            
        case .cannotStartWithoutParticipants:
            return "At least one student must be added as a participant before starting work."
            
        case .cannotCompleteWithoutSteps:
            return "Work must have at least one step defined before it can be completed."
            
        case .cannotCompleteWithIncompleteSteps(let count):
            return "\(count) step\(count == 1 ? " is" : "s are") not yet complete. All steps must be completed before finishing work."
            
        case .stepNotFound:
            return "The work step may have been deleted or does not exist."
            
        case .checkInNotFound:
            return "The check-in may have been deleted or does not exist."
            
        case .alreadyCompleted:
            return "This work item has already been marked as complete and cannot be modified."
            
        case .alreadyCancelled:
            return "This work item has been cancelled and cannot be modified."
            
        case .missingRequiredField(let field):
            return "The \(field) field is required to create or update work."
            
        case .invalidDuration(let duration):
            let minutes = Int(duration / 60)
            if duration < 0 {
                return "Duration cannot be negative."
            } else if duration > 86400 {
                return "Duration of \(minutes) minutes exceeds the maximum allowed (24 hours)."
            } else {
                return "Invalid duration value."
            }
            
        case .invalidObservation(let reason):
            return reason
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notFound:
            return "Refresh the work list and try again."
            
        case .invalidStatus:
            return "Select a valid status from the available options."
            
        case .invalidParticipant:
            return "Select a different student from the enrolled list."
            
        case .cannotStartWithoutParticipants:
            return "Add at least one student participant before starting the work."
            
        case .cannotCompleteWithoutSteps:
            return "Add work steps before marking as complete, or cancel the work if it's no longer needed."
            
        case .cannotCompleteWithIncompleteSteps:
            return "Complete all steps first, or remove incomplete steps if they're no longer needed."
            
        case .stepNotFound, .checkInNotFound:
            return "The item is no longer available. Please refresh and try again."
            
        case .alreadyCompleted:
            return "This work is already complete. Create a new work item if needed."
            
        case .alreadyCancelled:
            return "This work is cancelled. Create a new work item if needed."
            
        case .missingRequiredField(let field):
            return "Fill in the \(field) field before saving."
            
        case .invalidDuration:
            return "Enter a duration between 1 minute and 24 hours."
            
        case .invalidObservation:
            return "Review the observation text and try again."
        }
    }
}
