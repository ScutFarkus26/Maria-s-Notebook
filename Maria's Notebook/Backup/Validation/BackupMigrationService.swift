import Foundation
import SwiftData

/// Handles migration between backup format versions.
/// Current policy: only format version 6 is supported.
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
    /// Current policy does not support upgrading legacy versions.
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
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        let originalVersion = envelope.formatVersion
        let target = targetVersion ?? BackupFile.formatVersion

        guard originalVersion == target else {
            throw NSError(
                domain: "BackupMigrationService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No migration path from version \(originalVersion) to \(target). "
                        + "Only format version \(BackupFile.formatVersion) is supported."
                ]
            )
        }

        if createBackup {
            let backupURL = url.deletingPathExtension()
                .appendingPathExtension("v\(originalVersion).backup")
                .appendingPathExtension(url.pathExtension)
            try data.write(to: backupURL)
        }

        return MigrationResult(
            originalVersion: originalVersion,
            targetVersion: target,
            migrationsApplied: [],
            warnings: ["Backup is already at version \(target)"],
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

        guard originalVersion == target else {
            throw NSError(
                domain: "BackupMigrationService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No migration path from version \(originalVersion) to \(target). "
                        + "Only format version \(BackupFile.formatVersion) is supported."
                ]
            )
        }

        return MigrationPreview(
            originalVersion: originalVersion,
            targetVersion: target,
            steps: [],
            requiresBackup: false
        )
    }

    // MARK: - Built-in Migrations

    private func registerBuiltInMigrations() {
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

        if backupVersion == currentVersion {
            return .fullyCompatible
        }

        return .incompatible(reason: "Only backup format version \(currentVersion) is supported")
    }

    /// Gets information about a specific format version.
    public func versionInfo(for version: Int) -> FormatVersionInfo? {
        formatVersions.first { $0.version == version }
    }

    // MARK: - Version Information

    private let formatVersions: [FormatVersionInfo] = [
        FormatVersionInfo(
            version: 6,
            releaseDate: "2025-06-01",
            features: ["LZFSE compression", "Encrypted compression", "Backward compatible"],
            deprecationDate: nil
        )
    ]
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

public struct FormatVersionInfo {
    public let version: Int
    public let releaseDate: String
    public let features: [String]
    public let deprecationDate: String?

    public var isDeprecated: Bool {
        deprecationDate != nil
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
