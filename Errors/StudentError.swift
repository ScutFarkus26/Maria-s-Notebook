//
//  StudentError.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import Foundation

/// Errors related to student management operations
enum StudentError: AppError {
    case notFound(id: UUID)
    case duplicateName(firstName: String, lastName: String)
    case invalidBirthdate(date: Date)
    case invalidLevel(level: String)
    case cannotDeleteWithActiveLessons(studentName: String, lessonCount: Int)
    case cannotDeleteWithActiveWork(studentName: String, workCount: Int)
    case cannotDeleteWithNotes(studentName: String, noteCount: Int)
    case missingRequiredField(field: String)
    case invalidPhotoData
    case photoStorageFailed(underlying: Error)
    
    var category: ErrorCategory {
        switch self {
        case .notFound:
            return .notFound
        case .duplicateName:
            return .conflict
        case .invalidBirthdate, .invalidLevel, .missingRequiredField, .invalidPhotoData:
            return .validation
        case .cannotDeleteWithActiveLessons, .cannotDeleteWithActiveWork, .cannotDeleteWithNotes:
            return .business
        case .photoStorageFailed:
            return .system
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .notFound, .photoStorageFailed:
            return false
        case .duplicateName, .invalidBirthdate, .invalidLevel, .cannotDeleteWithActiveLessons,
             .cannotDeleteWithActiveWork, .cannotDeleteWithNotes, .missingRequiredField, .invalidPhotoData:
            return true
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Student not found"
            
        case .duplicateName(let first, let last):
            return "Duplicate student name"
            
        case .invalidBirthdate(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Invalid birthdate"
            
        case .invalidLevel(let level):
            return "Invalid level: \(level)"
            
        case .cannotDeleteWithActiveLessons(let name, let count):
            return "Cannot delete \(name)"
            
        case .cannotDeleteWithActiveWork(let name, let count):
            return "Cannot delete \(name)"
            
        case .cannotDeleteWithNotes(let name, let count):
            return "Cannot delete \(name)"
            
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
            
        case .invalidPhotoData:
            return "Invalid photo data"
            
        case .photoStorageFailed:
            return "Failed to save photo"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .notFound:
            return "The student may have been deleted or does not exist."
            
        case .duplicateName(let first, let last):
            return "A student named \(first) \(last) already exists in the system."
            
        case .invalidBirthdate(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            if date > Date() {
                return "The birthdate \(formatter.string(from: date)) is in the future."
            } else {
                return "The birthdate \(formatter.string(from: date)) is invalid."
            }
            
        case .invalidLevel(let level):
            return "'\(level)' is not a valid student level."
            
        case .cannotDeleteWithActiveLessons(let name, let count):
            return "\(name) has \(count) active lesson\(count == 1 ? "" : "s"). Students with active lessons cannot be deleted."
            
        case .cannotDeleteWithActiveWork(let name, let count):
            return "\(name) has \(count) active work item\(count == 1 ? "" : "s"). Students with active work cannot be deleted."
            
        case .cannotDeleteWithNotes(let name, let count):
            return "\(name) has \(count) note\(count == 1 ? "" : "s"). Students with notes cannot be deleted."
            
        case .missingRequiredField(let field):
            return "The \(field) field is required to create or update a student."
            
        case .invalidPhotoData:
            return "The selected photo could not be processed."
            
        case .photoStorageFailed(let error):
            return "Photo storage failed: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notFound:
            return "Refresh the student list and try again."
            
        case .duplicateName:
            return "Use a different name or add additional information to distinguish this student."
            
        case .invalidBirthdate:
            return "Enter a valid birthdate in the past."
            
        case .invalidLevel:
            return "Select a valid level from the available options."
            
        case .cannotDeleteWithActiveLessons(let name, _):
            return "Archive or remove \(name)'s lessons before deleting, or use the Archive feature instead of Delete."
            
        case .cannotDeleteWithActiveWork(let name, _):
            return "Complete or cancel \(name)'s work items before deleting, or use the Archive feature."
            
        case .cannotDeleteWithNotes(let name, _):
            return "Delete \(name)'s notes first, or use the Archive feature to preserve the notes."
            
        case .missingRequiredField(let field):
            return "Fill in the \(field) field before saving."
            
        case .invalidPhotoData:
            return "Try selecting a different photo or take a new one."
            
        case .photoStorageFailed:
            return "Check available storage space and try again."
        }
    }
}
