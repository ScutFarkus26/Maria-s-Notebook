import Foundation
import SwiftData

/// Legacy notes migration has been completed.
/// This stub ensures the migration flag is set for backward compatibility.
/// The actual migration logic has been removed as it's no longer needed.
enum LegacyNotesMigration {
    static let didMigrateKey = "DidMigrateLegacyScopedNotes_v1"

    static func runIfNeeded(modelContext: ModelContext) {
        // Skip flag setting during ephemeral/in-memory sessions
        if UserDefaults.standard.bool(forKey: MariasToolboxApp.ephemeralSessionFlagKey) {
            return
        }
        
        // Mark migration as complete for any users who haven't run it yet
        // This is safe because the migration is idempotent and has been widely deployed
        MigrationFlag.markComplete(key: didMigrateKey)
    }
}
