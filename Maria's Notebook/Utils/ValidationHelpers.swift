import Foundation

/// Helper functions for common validation patterns.
/// Reduces duplication in validation logic across the app.
enum ValidationHelpers {
    /// Validates that a string is not empty after trimming.
    /// - Parameters:
    ///   - value: The string to validate
    ///   - message: The error message if validation fails
    /// - Throws: ValidationError if the string is empty
    static func validateNonEmpty(
        _ value: String,
        message: String = "Value cannot be empty"
    ) throws {
        if value.trimmed().isEmpty {
            throw ValidationError.emptyValue(message)
        }
    }
    
    /// Validates that an optional value is not nil.
    /// - Parameters:
    ///   - value: The optional value to validate
    ///   - message: The error message if validation fails
    /// - Throws: ValidationError if the value is nil
    static func validateNotNil<T>(
        _ value: T?,
        message: String = "Value cannot be nil"
    ) throws -> T {
        guard let unwrapped = value else {
            throw ValidationError.nilValue(message)
        }
        return unwrapped
    }
    
    /// Validates that a value is within a range.
    /// - Parameters:
    ///   - value: The value to validate
    ///   - range: The valid range
    ///   - message: The error message if validation fails
    /// - Throws: ValidationError if the value is out of range
    static func validateRange<T: Comparable>(
        _ value: T,
        in range: ClosedRange<T>,
        message: String = "Value is out of range"
    ) throws {
        if !range.contains(value) {
            throw ValidationError.outOfRange(message)
        }
    }
    
    /// Validates that a collection is not empty.
    /// - Parameters:
    ///   - collection: The collection to validate
    ///   - message: The error message if validation fails
    /// - Throws: ValidationError if the collection is empty
    static func validateNonEmpty<C: Collection>(
        _ collection: C,
        message: String = "Collection cannot be empty"
    ) throws {
        if collection.isEmpty {
            throw ValidationError.emptyCollection(message)
        }
    }
}

/// Common validation errors
enum ValidationError: Error, LocalizedError {
    case emptyValue(String)
    case nilValue(String)
    case outOfRange(String)
    case emptyCollection(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyValue(let message), .nilValue(let message), .outOfRange(let message), .emptyCollection(let message):
            return message
        }
    }
}




