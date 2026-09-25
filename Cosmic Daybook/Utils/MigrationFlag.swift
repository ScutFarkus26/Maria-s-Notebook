import Foundation

/// Utility for managing migration flags in UserDefaults.
/// Encapsulates the common pattern of checking and setting migration completion flags.
nonisolated enum MigrationFlag {
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
}
