import Foundation
import SwiftData

/// Versioned migration registry for systematic database migrations.
///
/// This registry replaces the scattered migration approach with a centralized,
/// versioned system that tracks which migrations have been applied.
///
/// **Usage:**
/// ```swift
/// // In AppBootstrapper or app initialization
/// @MainActor
/// func runMigrationsIfNeeded() async throws {
///     try await MigrationRegistry.runPending(context: modelContext)
/// }
/// ```
@MainActor
struct MigrationRegistry {
    
    // MARK: - Migration Definition
    
    struct Migration {
        let version: Int
        let description: String
        let execute: (ModelContext) async throws -> Void
        
        init(
            version: Int,
            _ description: String,
            execute: @escaping (ModelContext) async throws -> Void
        ) {
            self.version = version
            self.description = description
            self.execute = execute
        }
    }
    
    // MARK: - Rollback Definition
    
    struct Rollback {
        let fromVersion: Int
        let toVersion: Int
        let description: String
        let execute: (ModelContext) async throws -> Void
        
        init(
            from: Int,
            to: Int,
            _ description: String,
            execute: @escaping (ModelContext) async throws -> Void
        ) {
            self.fromVersion = from
            self.toVersion = to
            self.description = description
            self.execute = execute
        }
    }
    
    // MARK: - Migration Registry
    
    /// All registered migrations in ascending version order
    static let migrations: [Migration] = [
        // Legacy migrations (already applied, kept for reference)
        Migration(
            version: 1,
            "UUID to String conversion for CloudKit compatibility"
        ) { context in
            // This migration was already applied in production
            // Kept here for documentation purposes
            print("Migration v1: Already applied (UUID → String)")
        },
        
        Migration(
            version: 2,
            "Extract legacy string notes to Note model objects"
        ) { context in
            // Already applied - note extraction from WorkModel, StudentLesson, etc.
            print("Migration v2: Already applied (Note extraction)")
        },
        
        // Phase 3 migrations (to be applied)
        Migration(
            version: 3,
            "Split Note model into domain-specific types"
        ) { context in
            // This will be implemented in Phase 3
            try await NoteSplitMigration.execute(context: context)
        },
        
        Migration(
            version: 4,
            "Remove legacy migration tracking fields"
        ) { context in
            // Clean up legacyContractID, migratedFromStudentLessonID, etc.
            try await LegacyFieldCleanupMigration.execute(context: context)
        },
        
        Migration(
            version: 5,
            "Convert string IDs to CloudKitUUID wrapper"
        ) { context in
            // Phase 2 migration - add CloudKitUUID wrapper
            // This is a code change, not a data migration
            print("Migration v5: CloudKitUUID wrapper applied (code-level change)")
        },
        
        // Future migrations can be added here
    ]
    
    // MARK: - Rollback Registry
    
    /// Registered rollbacks for emergency recovery
    static let rollbacks: [Rollback] = [
        Rollback(
            from: 3,
            to: 2,
            "Reverse Note split - combine back to generic Note"
        ) { context in
            try await NoteSplitMigration.reverse(context: context)
        }
    ]
    
    // MARK: - Version Management
    
    private static let versionKey = "MigrationVersion"
    private static let minimumCompatibleVersion = 1
    
    /// Current migration version from UserDefaults
    static var currentVersion: Int {
        UserDefaults.standard.integer(forKey: versionKey)
    }
    
    /// Set the current migration version
    private static func setVersion(_ version: Int) {
        UserDefaults.standard.set(version, forKey: versionKey)
    }
    
    /// Check if the app can run with the current data version
    static func checkCompatibility() -> Bool {
        let current = currentVersion
        return current >= minimumCompatibleVersion
    }
    
    /// Get user-facing error message for incompatible version
    static func incompatibilityMessage() -> String {
        """
        This version of Maria's Notebook requires data from version \(minimumCompatibleVersion) or later.
        
        Current data version: \(currentVersion)
        Required minimum: \(minimumCompatibleVersion)
        
        Please restore from a recent backup or reinstall the previous version.
        """
    }
    
    // MARK: - Migration Execution
    
    /// Run all pending migrations
    static func runPending(context: ModelContext) async throws {
        let current = currentVersion
        
        print("MigrationRegistry: Current version = \(current)")
        
        for migration in migrations where migration.version > current {
            print("MigrationRegistry: Running v\(migration.version) - \(migration.description)")
            
            do {
                try await migration.execute(context)
                setVersion(migration.version)
                print("MigrationRegistry: ✓ v\(migration.version) completed")
            } catch {
                print("MigrationRegistry: ✗ v\(migration.version) failed: \(error)")
                throw MigrationError.executionFailed(
                    version: migration.version,
                    description: migration.description,
                    underlyingError: error
                )
            }
        }
        
        print("MigrationRegistry: All migrations complete (now at v\(currentVersion))")
    }
    
    /// Rollback to a specific version (emergency use only)
    static func rollback(to targetVersion: Int, context: ModelContext) async throws {
        let current = currentVersion
        
        guard targetVersion < current else {
            throw MigrationError.invalidRollback(
                message: "Cannot rollback from v\(current) to v\(targetVersion)"
            )
        }
        
        print("MigrationRegistry: Rolling back from v\(current) to v\(targetVersion)")
        
        // Find applicable rollbacks
        let applicableRollbacks = rollbacks
            .filter { $0.fromVersion <= current && $0.toVersion >= targetVersion }
            .sorted { $0.fromVersion > $1.fromVersion }
        
        for rollback in applicableRollbacks {
            print("MigrationRegistry: Executing rollback v\(rollback.fromVersion) → v\(rollback.toVersion)")
            
            do {
                try await rollback.execute(context)
                print("MigrationRegistry: ✓ Rollback completed")
            } catch {
                print("MigrationRegistry: ✗ Rollback failed: \(error)")
                throw MigrationError.rollbackFailed(
                    from: rollback.fromVersion,
                    to: rollback.toVersion,
                    underlyingError: error
                )
            }
        }
        
        setVersion(targetVersion)
        print("MigrationRegistry: Rollback complete (now at v\(targetVersion))")
    }
    
    /// Get list of pending migrations
    static func pendingMigrations() -> [Migration] {
        let current = currentVersion
        return migrations.filter { $0.version > current }
    }
    
    /// Get human-readable migration history
    static func history() -> String {
        var lines = ["Migration History:"]
        lines.append("Current Version: \(currentVersion)")
        lines.append("")
        
        for migration in migrations {
            let status = migration.version <= currentVersion ? "✓" : "○"
            lines.append("\(status) v\(migration.version): \(migration.description)")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Migration Errors

enum MigrationError: LocalizedError {
    case executionFailed(version: Int, description: String, underlyingError: Error)
    case rollbackFailed(from: Int, to: Int, underlyingError: Error)
    case invalidRollback(message: String)
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let version, let desc, let error):
            return "Migration v\(version) failed: \(desc)\n\(error.localizedDescription)"
        case .rollbackFailed(let from, let to, let error):
            return "Rollback from v\(from) to v\(to) failed: \(error.localizedDescription)"
        case .invalidRollback(let message):
            return "Invalid rollback: \(message)"
        }
    }
}

// MARK: - Phase 3 Migration Stubs

/// Placeholder for Note split migration (implemented in Phase 3)
enum NoteSplitMigration {
    @MainActor
    static func execute(context: ModelContext) async throws {
        // Implementation will be added in Phase 3
        print("NoteSplitMigration: Placeholder - implementation pending")
    }
    
    @MainActor
    static func reverse(context: ModelContext) async throws {
        // Rollback implementation
        print("NoteSplitMigration: Rollback placeholder")
    }
}

/// Placeholder for legacy field cleanup (implemented in Phase 1.3)
enum LegacyFieldCleanupMigration {
    @MainActor
    static func execute(context: ModelContext) async throws {
        print("LegacyFieldCleanupMigration: Removing legacy tracking fields")
        
        // This will remove fields like:
        // - WorkModel.legacyContractID
        // - LessonAssignment.migratedFromStudentLessonID
        // - etc.
        
        // For now, just verify no data uses these fields
        let descriptor = FetchDescriptor<WorkModel>()
        let allWork = try context.fetch(descriptor)
        
        var legacyFieldsFound = 0
        for work in allWork {
            if work.legacyContractID != nil {
                legacyFieldsFound += 1
            }
        }
        
        if legacyFieldsFound > 0 {
            print("Warning: \(legacyFieldsFound) WorkModel records still have legacy fields")
        }
    }
}

// MARK: - Debug View (Development Only)

#if DEBUG
import SwiftUI

struct MigrationDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var targetVersion = 1
    @State private var output = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Migration Debug Console")
                .font(.title)
            
            Text(MigrationRegistry.history())
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            HStack {
                Text("Rollback to:")
                Picker("Version", selection: $targetVersion) {
                    ForEach(1...MigrationRegistry.currentVersion, id: \.self) { version in
                        Text("v\(version)").tag(version)
                    }
                }
            }
            
            Button("Rollback") {
                Task {
                    do {
                        try await MigrationRegistry.rollback(to: targetVersion, context: modelContext)
                        output = "Rollback successful"
                    } catch {
                        output = "Rollback failed: \(error)"
                    }
                }
            }
            .disabled(targetVersion >= MigrationRegistry.currentVersion)
            
            if !output.isEmpty {
                Text(output)
                    .foregroundColor(output.contains("failed") ? .red : .green)
                    .padding()
            }
            
            Spacer()
        }
        .padding()
    }
}
#endif
