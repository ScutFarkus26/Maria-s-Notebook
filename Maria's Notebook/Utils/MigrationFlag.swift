import Foundation

/// Utility for managing migration flags in UserDefaults.
/// Encapsulates the common pattern of checking and setting migration completion flags.
enum MigrationFlag {
    /// Runs a migration closure only if the flag hasn't been set.
    /// - Parameters:
    ///   - key: The UserDefaults key for the migration flag
    ///   - migration: The migration closure to execute if needed
    /// - Returns: `true` if migration was run, `false` if already completed
    @discardableResult
    static func runIfNeeded(key: String, migration: () throws -> Void) rethrows -> Bool {
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        try migration()
        UserDefaults.standard.set(true, forKey: key)
        return true
    }
    
    /// Runs an async migration closure only if the flag hasn't been set.
    /// - Parameters:
    ///   - key: The UserDefaults key for the migration flag
    ///   - migration: The async migration closure to execute if needed
    /// - Returns: `true` if migration was run, `false` if already completed
    @discardableResult
    static func runIfNeeded(key: String, migration: () async throws -> Void) async rethrows -> Bool {
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        try await migration()
        UserDefaults.standard.set(true, forKey: key)
        return true
    }
    
    /// Checks if a migration has already been completed.
    /// - Parameter key: The UserDefaults key for the migration flag
    /// - Returns: `true` if migration is complete, `false` otherwise
    static func isComplete(key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
    
    /// Manually marks a migration as complete.
    /// - Parameter key: The UserDefaults key for the migration flag
    static func markComplete(key: String) {
        UserDefaults.standard.set(true, forKey: key)
    }
    
    /// Resets a migration flag (useful for testing or re-running migrations).
    /// - Parameter key: The UserDefaults key for the migration flag
    static func reset(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

