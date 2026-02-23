import Foundation

/// Helper functions for common optional binding patterns.
/// Reduces boilerplate in optional chaining and nil-coalescing operations.
enum OptionalBindingHelpers {
    /// Unwraps an optional and applies a transformation, returning a fallback if nil.
    /// - Parameters:
    ///   - optional: The optional value
    ///   - transform: The transformation function
    ///   - fallback: The fallback value if optional is nil
    /// - Returns: The transformed value or fallback
    static func unwrap<T, U>(
        _ optional: T?,
        transform: (T) -> U,
        fallback: U
    ) -> U {
        guard let value = optional else { return fallback }
        return transform(value)
    }
    
    /// Unwraps an optional and applies a transformation, returning nil if the optional is nil.
    /// - Parameters:
    ///   - optional: The optional value
    ///   - transform: The transformation function
    /// - Returns: The transformed value or nil
    static func unwrap<T, U>(
        _ optional: T?,
        transform: (T) -> U?
    ) -> U? {
        guard let value = optional else { return nil }
        return transform(value)
    }
    
    /// Chains two optional operations.
    /// - Parameters:
    ///   - optional: The first optional
    ///   - transform: The transformation that returns another optional
    /// - Returns: The final optional value
    static func chain<T, U>(
        _ optional: T?,
        transform: (T) -> U?
    ) -> U? {
        guard let value = optional else { return nil }
        return transform(value)
    }
    
    /// Chains three optional operations.
    /// - Parameters:
    ///   - optional: The first optional
    ///   - transform1: The first transformation
    ///   - transform2: The second transformation
    /// - Returns: The final optional value
    static func chain<T, U, V>(
        _ optional: T?,
        transform1: (T) -> U?,
        transform2: (U) -> V?
    ) -> V? {
        guard let value = optional,
              let intermediate = transform1(value) else { return nil }
        return transform2(intermediate)
    }
}




