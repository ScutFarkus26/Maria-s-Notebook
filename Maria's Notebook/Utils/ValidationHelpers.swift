import Foundation

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
