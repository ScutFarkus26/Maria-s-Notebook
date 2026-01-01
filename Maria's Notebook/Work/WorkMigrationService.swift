import Foundation
import SwiftData

/// Work migration entry point (deactivated)
///
/// Legacy WorkModel-based migrations have been fully removed in the second pass.
/// This type remains to keep call sites stable, but performs no work.
enum WorkMigrationService {
    private static let flagKey = "WorkMigration.v1.completed"

    static func runIfNeeded(using context: ModelContext) {
        // If a previous app version set this flag, leave it alone.
        // Otherwise, set it now to avoid repeated attempts.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: flagKey) {
            return
        }
        do {
            try performMigration(using: context)
            try context.save()
            defaults.set(true, forKey: flagKey)
            defaults.synchronize()
        } catch {
            // No-op: migration is disabled; retain safety logging in DEBUG builds.
            #if DEBUG
            print("WorkMigrationService (disabled) error: \(error)")
            #endif
        }
    }

    // MARK: - Core Migration (disabled)
    private static func performMigration(using context: ModelContext) throws {
        // Second pass: Legacy WorkModel has been stripped.
        // This function intentionally does nothing to avoid touching legacy types.
        // Keeping the method preserves binary/source compatibility for callers.
        return
    }
}
