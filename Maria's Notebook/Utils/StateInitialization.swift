import Foundation
import SwiftUI

/// Helper utilities for common state initialization patterns.
/// Reduces boilerplate in view initialization.
enum StateInitialization {
    /// Initializes a string state from UserDefaults with optional trimming.
    /// - Parameters:
    ///   - key: UserDefaults key
    ///   - defaultValue: Default value if key doesn't exist
    ///   - trim: Whether to trim whitespace (default: true)
    /// - Returns: Initialized string value
    static func stringFromDefaults(
        key: String,
        defaultValue: String = "",
        trim: Bool = true
    ) -> String {
        let value = UserDefaults.standard.string(forKey: key) ?? defaultValue
        return trim ? value.trimmed() : value
    }
    
    /// Initializes a boolean state from UserDefaults.
    /// - Parameters:
    ///   - key: UserDefaults key
    ///   - defaultValue: Default value if key doesn't exist
    /// - Returns: Initialized boolean value
    static func boolFromDefaults(
        key: String,
        defaultValue: Bool = false
    ) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
    
    /// Initializes an integer state from UserDefaults.
    /// - Parameters:
    ///   - key: UserDefaults key
    ///   - defaultValue: Default value if key doesn't exist
    /// - Returns: Initialized integer value
    static func intFromDefaults(
        key: String,
        defaultValue: Int = 0
    ) -> Int {
        UserDefaults.standard.integer(forKey: key)
    }
    
    /// Initializes a double state from UserDefaults.
    /// - Parameters:
    ///   - key: UserDefaults key
    ///   - defaultValue: Default value if key doesn't exist
    /// - Returns: Initialized double value
    static func doubleFromDefaults(
        key: String,
        defaultValue: Double = 0.0
    ) -> Double {
        UserDefaults.standard.double(forKey: key)
    }
}

/// Property wrapper for optional state that can be initialized from UserDefaults.
@propertyWrapper
struct OptionalStateFromDefaults<T>: DynamicProperty {
    private let key: String
    private let defaultValue: T?
    
    @State private var value: T?
    
    var wrappedValue: T? {
        get { value }
        nonmutating set {
            value = newValue
            if let newValue = newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    
    init(key: String, defaultValue: T? = nil) {
        self.key = key
        self.defaultValue = defaultValue
        let stored = UserDefaults.standard.object(forKey: key) as? T
        _value = State(initialValue: stored ?? defaultValue)
    }
}
