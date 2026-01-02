import Foundation

/// Helper functions for consistent async error handling patterns.
/// Reduces duplication in view models and services that perform async operations.
enum AsyncErrorHandling {
    /// Executes an async operation with error handling, setting an error message on failure.
    /// - Parameters:
    ///   - operation: The async operation to execute
    ///   - errorMessage: Binding to set error message on failure
    ///   - onSuccess: Optional callback on success
    /// - Returns: The result of the operation, or nil on error
    @discardableResult
    static func execute<T>(
        operation: () async throws -> T,
        errorMessage: inout String?,
        onSuccess: ((T) -> Void)? = nil
    ) async -> T? {
        do {
            let result = try await operation()
            errorMessage = nil
            onSuccess?(result)
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
    
    /// Executes an async operation with error handling, calling a completion handler.
    /// - Parameters:
    ///   - operation: The async operation to execute
    ///   - onCompletion: Handler called with result or error
    static func execute<T>(
        operation: () async throws -> T,
        onCompletion: @escaping (Result<T, Error>) -> Void
    ) async {
        do {
            let result = try await operation()
            onCompletion(.success(result))
        } catch {
            onCompletion(.failure(error))
        }
    }
    
    /// Executes an async operation with loading state management.
    /// - Parameters:
    ///   - isLoading: Binding to track loading state
    ///   - errorMessage: Binding to set error message on failure
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation, or nil on error
    @discardableResult
    static func executeWithLoading<T>(
        isLoading: inout Bool,
        errorMessage: inout String?,
        operation: () async throws -> T
    ) async -> T? {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await operation()
            errorMessage = nil
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}


