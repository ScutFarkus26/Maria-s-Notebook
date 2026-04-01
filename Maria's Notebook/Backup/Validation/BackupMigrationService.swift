import Foundation
import CoreData

/// Handles migration between backup format versions.
/// Supports importing backups from v5 (minimum checksummed version) through the current version.
/// Because newer payload fields are optional arrays that decode as nil from older backups,
/// no payload transformation is needed — only the envelope's formatVersion stamp is updated.
@MainActor
public final class BackupMigrationService {

    // MARK: - Types

    public struct MigrationPath {
        public let fromVersion: Int
        public let toVersion: Int
        public let migrator: (BackupEnvelope) throws -> BackupEnvelope
        public let description: String
        public let isDestructive: Bool
    }

    public struct MigrationResult {
        public let originalVersion: Int
        public let targetVersion: Int
        public let migrationsApplied: [String]
        public let warnings: [String]
        public let success: Bool
    }

    // MARK: - Migration Registry

    private var registeredMigrations: [MigrationPath] = []

    public init() {
        registerBuiltInMigrations()
    }

    // MARK: - Migration

    /// Migrates a backup file to the latest format version.
    /// For v5+, newer optional payload arrays decode as nil so no payload rewrite is needed —
    /// only the envelope formatVersion is stamped to the target.
    public func migrate(
        backupAt url: URL,
        to targetVersion: Int? = nil,
        createBackup: Bool = true
    ) async throws -> MigrationResult {

        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var envelope = try decoder.decode(BackupEnvelope.self, from: data)

        let originalVersion = envelope.formatVersion
        let target = targetVersion ?? BackupFile.formatVersion
        let minSupported = BackupMigrationManifest.minimumSupportedVersion

        // Already at target
        if originalVersion == target {
            return MigrationResult(
                originalVersion: originalVersion,
                targetVersion: target,
                migrationsApplied: [],
                warnings: ["Backup is already at version \(target)"],
                success: true
            )
        }

        // Too old — below minimum supported version
        guard originalVersion >= minSupported else {
            throw NSError(
                domain: "BackupMigrationService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Backup format v\(originalVersion) is too old. "
                        + "Minimum supported version is v\(minSupported)."
                ]
            )
        }

        // Future version — app needs updating
        guard originalVersion <= target else {
            throw NSError(
                domain: "BackupMigrationService",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Backup was created with a newer app version (v\(originalVersion)). "
                        + "Please update the app to restore this backup."
                ]
            )
        }

        // Create a safety copy before modifying
        if createBackup {
            let backupURL = url.deletingPathExtension()
                .appendingPathExtension("v\(originalVersion).backup")
                .appendingPathExtension(url.pathExtension)
            try data.write(to: backupURL)
        }

        // Apply registered migrations in order
        var applied: [String] = []
        var warnings: [String] = []
        var currentVersion = originalVersion

        while currentVersion < target {
            if let migration = registeredMigrations.first(where: {
                $0.fromVersion == currentVersion
            }) {
                envelope = try migration.migrator(envelope)
                applied.append(migration.description)
                currentVersion = migration.toVersion
            } else {
                // No explicit migration registered — stamp the version forward.
                // This is safe because newer payload fields are optional and decode as nil.
                let skippedTo = target
                warnings.append(
                    "No explicit migration from v\(currentVersion) to v\(skippedTo); "
                    + "optional payload fields will be nil for entity types introduced after v\(currentVersion)."
                )
                envelope.formatVersion = skippedTo
                currentVersion = skippedTo
            }
        }

        // Write migrated envelope back
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let migratedData = try encoder.encode(envelope)
        try migratedData.write(to: url)

        return MigrationResult(
            originalVersion: originalVersion,
            targetVersion: target,
            migrationsApplied: applied,
            warnings: warnings,
            success: true
        )
    }

    /// Previews what would happen during migration without applying changes.
    public func previewMigration(
        backupAt url: URL,
        to targetVersion: Int? = nil
    ) async throws -> MigrationPreview {

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        let originalVersion = envelope.formatVersion
        let target = targetVersion ?? BackupFile.formatVersion
        let minSupported = BackupMigrationManifest.minimumSupportedVersion

        guard originalVersion >= minSupported else {
            throw NSError(
                domain: "BackupMigrationService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Backup format v\(originalVersion) is too old. "
                        + "Minimum supported version is v\(minSupported)."
                ]
            )
        }

        // Build preview steps from version history
        var steps: [MigrationPreviewStep] = []
        let history = BackupMigrationManifest.versionHistory
            .filter { $0.version > originalVersion && $0.version <= target }
            .sorted { $0.version < $1.version }

        for info in history {
            let prevVersion = steps.last?.toVersion ?? originalVersion
            steps.append(MigrationPreviewStep(
                fromVersion: prevVersion,
                toVersion: info.version,
                description: info.description,
                isDestructive: info.hasBreakingChanges
            ))
        }

        return MigrationPreview(
            originalVersion: originalVersion,
            targetVersion: target,
            steps: steps,
            requiresBackup: steps.contains { $0.isDestructive }
        )
    }

    // MARK: - Built-in Migrations

    private func registerBuiltInMigrations() {
        // No explicit payload transformations are needed between v5 and v13 because:
        // 1. All new fields since v8 are optional arrays that decode as nil from older JSON
        // 2. Compression (v6) is handled at the envelope level, not the payload level
        // 3. Removed fields (WorkPlanItem in v7, LegacyPresentation in v11) are simply ignored
        //
        // If a future version requires actual payload transformation (e.g., renaming a field
        // or changing a type), register a MigrationPath here with the appropriate migrator closure.
        registeredMigrations = []
    }

    // MARK: - Registration

    public func register(_ migration: MigrationPath) {
        registeredMigrations.append(migration)
    }

    // MARK: - Compatibility Checking

    /// Checks if a backup version is compatible with current app version.
    public func isCompatible(backupVersion: Int) -> BackupCompatibility {
        let currentVersion = BackupFile.formatVersion
        let minSupported = BackupMigrationManifest.minimumSupportedVersion

        if backupVersion == currentVersion {
            return .fullyCompatible
        }

        if backupVersion >= minSupported && backupVersion < currentVersion {
            return .compatibleWithMigration
        }

        if backupVersion > currentVersion {
            return .incompatible(
                reason: "Backup was created with a newer app version (v\(backupVersion)). Update the app."
            )
        }

        return .incompatible(
            reason: "Backup format v\(backupVersion) is too old. "
                + "Minimum supported version is v\(minSupported)."
        )
    }

    /// Gets information about a specific format version.
    public func versionInfo(for version: Int) -> BackupMigrationManifest.FormatVersionInfo? {
        BackupMigrationManifest.versionHistory.first { $0.version == version }
    }
}

// MARK: - Supporting Types

public enum BackupCompatibility {
    case fullyCompatible
    case compatibleWithMigration
    case incompatible(reason: String)

    public var canRestore: Bool {
        switch self {
        case .fullyCompatible, .compatibleWithMigration:
            return true
        case .incompatible:
            return false
        }
    }
}

public struct MigrationPreview {
    public let originalVersion: Int
    public let targetVersion: Int
    public let steps: [MigrationPreviewStep]
    public let requiresBackup: Bool
}

public struct MigrationPreviewStep {
    public let fromVersion: Int
    public let toVersion: Int
    public let description: String
    public let isDestructive: Bool
}
