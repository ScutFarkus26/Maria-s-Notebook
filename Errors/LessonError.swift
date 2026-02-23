//
//  LessonError.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import Foundation

/// Errors related to lesson management operations
enum LessonError: AppError {
    case notFound(id: UUID)
    case duplicateTitle(subject: String, group: String)
    case invalidSubject(subject: String)
    case invalidGroup(group: String)
    case missingRequiredField(field: String)
    case cannotDeleteWithActivePresentations(lessonTitle: String, presentationCount: Int)
    case cannotDeleteWithAttachments(lessonTitle: String, attachmentCount: Int)
    case attachmentNotFound(id: UUID)
    case attachmentSizeTooLarge(size: Int64, maxSize: Int64)
    case unsupportedAttachmentType(fileExtension: String)
    case attachmentStorageFailed(underlying: Error)
    
    var category: ErrorCategory {
        switch self {
        case .notFound, .attachmentNotFound:
            return .notFound
        case .duplicateTitle:
            return .conflict
        case .invalidSubject, .invalidGroup, .missingRequiredField, .attachmentSizeTooLarge, .unsupportedAttachmentType:
            return .validation
        case .cannotDeleteWithActivePresentations, .cannotDeleteWithAttachments:
            return .business
        case .attachmentStorageFailed:
            return .system
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .notFound, .attachmentNotFound, .attachmentStorageFailed:
            return false
        case .duplicateTitle, .invalidSubject, .invalidGroup, .missingRequiredField,
             .cannotDeleteWithActivePresentations, .cannotDeleteWithAttachments,
             .attachmentSizeTooLarge, .unsupportedAttachmentType:
            return true
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Lesson not found"
            
        case .duplicateTitle(let subject, let group):
            return "Duplicate lesson"
            
        case .invalidSubject:
            return "Invalid subject"
            
        case .invalidGroup:
            return "Invalid group"
            
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
            
        case .cannotDeleteWithActivePresentations(let title, _):
            return "Cannot delete \(title)"
            
        case .cannotDeleteWithAttachments(let title, _):
            return "Cannot delete \(title)"
            
        case .attachmentNotFound:
            return "Attachment not found"
            
        case .attachmentSizeTooLarge(let size, let maxSize):
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            return "Attachment too large"
            
        case .unsupportedAttachmentType(let ext):
            return "Unsupported file type: .\(ext)"
            
        case .attachmentStorageFailed:
            return "Failed to save attachment"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .notFound:
            return "The lesson may have been deleted or does not exist."
            
        case .duplicateTitle(let subject, let group):
            return "A lesson for '\(subject)' in group '\(group)' already exists."
            
        case .invalidSubject(let subject):
            return "'\(subject)' is not a valid subject."
            
        case .invalidGroup(let group):
            return "'\(group)' is not a valid group."
            
        case .missingRequiredField(let field):
            return "The \(field) field is required to create or update a lesson."
            
        case .cannotDeleteWithActivePresentations(let title, let count):
            return "\(title) has \(count) scheduled presentation\(count == 1 ? "" : "s"). Lessons with presentations cannot be deleted."
            
        case .cannotDeleteWithAttachments(let title, let count):
            return "\(title) has \(count) attachment\(count == 1 ? "" : "s"). Remove attachments before deleting the lesson."
            
        case .attachmentNotFound:
            return "The attachment may have been deleted or moved."
            
        case .attachmentSizeTooLarge(let size, let maxSize):
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            return "The file (\(formatter.string(fromByteCount: size))) exceeds the maximum size of \(formatter.string(fromByteCount: maxSize))."
            
        case .unsupportedAttachmentType(let ext):
            return "Files with the .\(ext) extension are not supported."
            
        case .attachmentStorageFailed(let error):
            return "Attachment storage failed: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notFound:
            return "Refresh the lesson list and try again."
            
        case .duplicateTitle:
            return "Use a different title or add additional details to distinguish this lesson."
            
        case .invalidSubject:
            return "Select a subject from the available options or create a new subject area."
            
        case .invalidGroup:
            return "Select a group from the available options."
            
        case .missingRequiredField(let field):
            return "Fill in the \(field) field before saving."
            
        case .cannotDeleteWithActivePresentations(let title, _):
            return "Cancel or complete the presentations for '\(title)' before deleting, or use the Archive feature."
            
        case .cannotDeleteWithAttachments:
            return "Delete the attachments first, then try deleting the lesson again."
            
        case .attachmentNotFound:
            return "The attachment is no longer available. You may need to re-upload it."
            
        case .attachmentSizeTooLarge(_, let maxSize):
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            return "Compress the file or select a smaller file (max \(formatter.string(fromByteCount: maxSize)))."
            
        case .unsupportedAttachmentType:
            return "Please use a supported file type (PDF, images, videos, or documents)."
            
        case .attachmentStorageFailed:
            return "Check available storage space and try again."
        }
    }
}
