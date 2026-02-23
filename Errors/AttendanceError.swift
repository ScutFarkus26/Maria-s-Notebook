//
//  AttendanceError.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import Foundation

/// Errors related to attendance tracking operations
enum AttendanceError: AppError {
    case notFound(studentID: UUID, date: Date)
    case duplicateRecord(studentID: UUID, date: Date)
    case invalidStatus(status: String)
    case invalidDate(date: Date)
    case futureDate(date: Date)
    case nonSchoolDay(date: Date)
    case studentNotFound(id: UUID)
    case missingRequiredField(field: String)
    case emailGenerationFailed(studentNames: [String], underlying: Error?)
    case emailSendFailed(underlying: Error)
    
    var category: ErrorCategory {
        switch self {
        case .notFound, .studentNotFound:
            return .notFound
        case .duplicateRecord:
            return .conflict
        case .invalidStatus, .invalidDate, .futureDate, .nonSchoolDay, .missingRequiredField:
            return .validation
        case .emailGenerationFailed, .emailSendFailed:
            return .system
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .notFound, .studentNotFound, .emailSendFailed:
            return false
        case .duplicateRecord, .invalidStatus, .invalidDate, .futureDate, .nonSchoolDay,
             .missingRequiredField, .emailGenerationFailed:
            return true
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .notFound(_, let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Attendance record not found for \(formatter.string(from: date))"
            
        case .duplicateRecord(_, let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Attendance already recorded for \(formatter.string(from: date))"
            
        case .invalidStatus(let status):
            return "Invalid attendance status: \(status)"
            
        case .invalidDate:
            return "Invalid date"
            
        case .futureDate(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Cannot record attendance for future date: \(formatter.string(from: date))"
            
        case .nonSchoolDay(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Not a school day: \(formatter.string(from: date))"
            
        case .studentNotFound:
            return "Student not found"
            
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
            
        case .emailGenerationFailed(let names, _):
            if names.count == 1 {
                return "Failed to generate absence email for \(names[0])"
            } else {
                return "Failed to generate absence emails for \(names.count) students"
            }
            
        case .emailSendFailed:
            return "Failed to send absence email"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .notFound(let studentID, let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "No attendance record exists for student \(studentID) on \(formatter.string(from: date))."
            
        case .duplicateRecord(let studentID, let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Attendance for student \(studentID) has already been recorded for \(formatter.string(from: date))."
            
        case .invalidStatus(let status):
            return "'\(status)' is not a valid attendance status. Valid values are: Present, Absent, Tardy."
            
        case .invalidDate(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            return "\(formatter.string(from: date)) is not a valid date."
            
        case .futureDate(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Attendance cannot be recorded for \(formatter.string(from: date)) because it is in the future."
            
        case .nonSchoolDay(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let calendar = Calendar.current
            if calendar.isDateInWeekend(date) {
                return "\(formatter.string(from: date)) is a weekend day."
            } else {
                return "\(formatter.string(from: date)) is marked as a non-school day (holiday or break)."
            }
            
        case .studentNotFound(let id):
            return "Student with ID \(id) does not exist or has been deleted."
            
        case .missingRequiredField(let field):
            return "The \(field) field is required to record attendance."
            
        case .emailGenerationFailed(let names, let error):
            let studentList = names.joined(separator: ", ")
            if let error = error {
                return "Failed to generate absence email for \(studentList): \(error.localizedDescription)"
            } else {
                return "Failed to generate absence email for \(studentList)."
            }
            
        case .emailSendFailed(let error):
            return "The email could not be sent: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notFound:
            return "Create a new attendance record for this date."
            
        case .duplicateRecord:
            return "Update the existing attendance record instead of creating a new one."
            
        case .invalidStatus:
            return "Select Present, Absent, or Tardy as the attendance status."
            
        case .invalidDate:
            return "Enter a valid date and try again."
            
        case .futureDate:
            return "Attendance can only be recorded for today or past dates."
            
        case .nonSchoolDay:
            return "Check the school calendar settings or select a different date."
            
        case .studentNotFound:
            return "Refresh the student list and try again."
            
        case .missingRequiredField(let field):
            return "Fill in the \(field) field before saving."
            
        case .emailGenerationFailed:
            return "Check email settings and try again, or manually send the absence notification."
            
        case .emailSendFailed:
            return "Check your email configuration and try again."
        }
    }
}
