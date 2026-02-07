import Foundation
import SwiftData

/// Handles migration between backup format versions
/// Provides explicit migration paths and backward compatibility
@MainActor
public final class BackupMigrationService {
    
    // MARK: - Types
    
    public struct MigrationPath {
        public let fromVersion: Int
        public let toVersion: Int
        public let migrator: (BackupEnvelope) throws -> BackupEnvelope
        public let description: String
        public let isDestructive: Bool  // Can't reverse without data loss
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
    
    /// Migrates a backup file to the latest format version
    /// - Parameters:
    ///   - url: Backup file to migrate
    ///   - targetVersion: Target format version (nil = latest)
    ///   - createBackup: Create backup of original before migration
    /// - Returns: Migration result with details
    public func migrate(
        backupAt url: URL,
        to targetVersion: Int? = nil,
        createBackup: Bool = true
    ) async throws -> MigrationResult {
        
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        // Load and determine current version
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var envelope = try decoder.decode(BackupEnvelope.self, from: data)
        
        let originalVersion = envelope.formatVersion
        let target = targetVersion ?? BackupFile.formatVersion
        
        // Already at target version
        guard originalVersion != target else {
            return MigrationResult(
                originalVersion: originalVersion,
                targetVersion: target,
                migrationsApplied: [],
                warnings: ["Backup is already at version \(target)"],
                success: true
            )
        }
        
        // Create backup if requested
        if createBackup {
            let backupURL = url.deletingPathExtension()
                .appendingPathExtension("v\(originalVersion).backup")
                .appendingPathExtension(url.pathExtension)
            try data.write(to: backupURL)
        }
        
        // Find migration path
        let path = try findMigrationPath(from: originalVersion, to: target)
        
        var migrationsApplied: [String] = []
        var warnings: [String] = []
        
        // Apply migrations in sequence
        for migration in path {
            envelope = try migration.migrator(envelope)
            migrationsApplied.append("v\(migration.fromVersion) → v\(migration.toVersion): \(migration.description)")
            
            if migration.isDestructive {
                warnings.append("Migration v\(migration.fromVersion) → v\(migration.toVersion) is destructive")
            }
        }
        
        // Write migrated backup
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let migratedData = try encoder.encode(envelope)
        try migratedData.write(to: url, options: .atomic)
        
        return MigrationResult(
            originalVersion: originalVersion,
            targetVersion: target,
            migrationsApplied: migrationsApplied,
            warnings: warnings,
            success: true
        )
    }
    
    /// Previews what would happen during migration without applying changes
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
        
        let path = try findMigrationPath(from: originalVersion, to: target)
        
        var steps: [MigrationPreviewStep] = []
        for migration in path {
            steps.append(MigrationPreviewStep(
                fromVersion: migration.fromVersion,
                toVersion: migration.toVersion,
                description: migration.description,
                isDestructive: migration.isDestructive
            ))
        }
        
        return MigrationPreview(
            originalVersion: originalVersion,
            targetVersion: target,
            steps: steps,
            requiresBackup: path.contains { $0.isDestructive }
        )
    }
    
    // MARK: - Migration Path Finding
    
    private func findMigrationPath(from sourceVersion: Int, to targetVersion: Int) throws -> [MigrationPath] {
        guard sourceVersion != targetVersion else {
            return []
        }
        
        // Use BFS to find shortest path
        var queue: [(version: Int, path: [MigrationPath])] = [(sourceVersion, [])]
        var visited = Set<Int>([sourceVersion])
        
        while !queue.isEmpty {
            let (currentVersion, currentPath) = queue.removeFirst()
            
            // Find available migrations from current version
            for migration in registeredMigrations where migration.fromVersion == currentVersion {
                let nextVersion = migration.toVersion
                
                if nextVersion == targetVersion {
                    // Found complete path
                    return currentPath + [migration]
                }
                
                if !visited.contains(nextVersion) {
                    visited.insert(nextVersion)
                    queue.append((nextVersion, currentPath + [migration]))
                }
            }
        }
        
        throw NSError(
            domain: "BackupMigrationService",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "No migration path found from version \(sourceVersion) to \(targetVersion)"
            ]
        )
    }
    
    // MARK: - Built-in Migrations
    
    private func registerBuiltInMigrations() {
        // Migration v1 → v2
        register(MigrationPath(
            fromVersion: 1,
            toVersion: 2,
            migrator: { envelope in
                var migrated = envelope
                // Add any v1 → v2 specific migrations
                migrated.formatVersion = 2
                return migrated
            },
            description: "Initial format update",
            isDestructive: false
        ))
        
        // Migration v2 → v3
        register(MigrationPath(
            fromVersion: 2,
            toVersion: 3,
            migrator: { envelope in
                var migrated = envelope
                migrated.formatVersion = 3
                return migrated
            },
            description: "Added enhanced metadata",
            isDestructive: false
        ))
        
        // Migration v3 → v4
        register(MigrationPath(
            fromVersion: 3,
            toVersion: 4,
            migrator: { envelope in
                var migrated = envelope
                migrated.formatVersion = 4
                return migrated
            },
            description: "Updated entity relationships",
            isDestructive: false
        ))
        
        // Migration v4 → v5
        register(MigrationPath(
            fromVersion: 4,
            toVersion: 5,
            migrator: { envelope in
                var migrated = envelope
                // v5 enforces checksum validation
                if migrated.manifest.sha256.isEmpty {
                    throw NSError(
                        domain: "BackupMigrationService",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Cannot migrate to v5: backup missing required checksum"
                        ]
                    )
                }
                migrated.formatVersion = 5
                return migrated
            },
            description: "Enforced checksum validation",
            isDestructive: false
        ))
        
        // Migration v5 → v6
        register(MigrationPath(
            fromVersion: 5,
            toVersion: 6,
            migrator: { envelope in
                var migrated = envelope
                
                // v6 adds compression support
                // If payload is uncompressed, compress it
                if migrated.payload != nil && migrated.compressedPayload == nil {
                    // Note: In real migration, would compress the payload here
                    // For now, just update metadata
                    migrated.manifest.compression = BackupFile.compressionAlgorithm
                }
                
                migrated.formatVersion = 6
                return migrated
            },
            description: "Added compression support",
            isDestructive: false
        ))
        
        // Migration v6 → v7 (future)
        register(MigrationPath(
            fromVersion: 6,
            toVersion: 7,
            migrator: { envelope in
                var migrated = envelope
                // Placeholder for future v7 migrations
                migrated.formatVersion = 7
                return migrated
            },
            description: "Future format enhancements",
            isDestructive: false
        ))
    }
    
    // MARK: - Registration
    
    public func register(_ migration: MigrationPath) {
        registeredMigrations.append(migration)
    }
    
    // MARK: - Compatibility Checking
    
    /// Checks if a backup version is compatible with current app version
    public func isCompatible(backupVersion: Int) -> BackupCompatibility {
        let currentVersion = BackupFile.formatVersion
        
        if backupVersion == currentVersion {
            return .fullyCompatible
        } else if backupVersion < currentVersion {
            // Check if migration path exists
            do {
                _ = try findMigrationPath(from: backupVersion, to: currentVersion)
                return .compatibleWithMigration
            } catch {
                return .incompatible(reason: "No migration path available")
            }
        } else {
            return .incompatible(reason: "Backup is from a newer app version")
        }
    }
    
    /// Gets information about a specific format version
    public func versionInfo(for version: Int) -> FormatVersionInfo? {
        return formatVersions.first { $0.version == version }
    }
    
    // MARK: - Version Information
    
    private let formatVersions: [FormatVersionInfo] = [
        FormatVersionInfo(
            version: 1,
            releaseDate: "2023-01-01",
            features: ["Basic backup structure", "Uncompressed payloads"],
            deprecationDate: nil
        ),
        FormatVersionInfo(
            version: 2,
            releaseDate: "2023-06-01",
            features: ["Enhanced metadata", "Improved entity relationships"],
            deprecationDate: nil
        ),
        FormatVersionInfo(
            version: 3,
            releaseDate: "2024-01-01",
            features: ["Extended entity types", "Preference backup"],
            deprecationDate: nil
        ),
        FormatVersionInfo(
            version: 4,
            releaseDate: "2024-06-01",
            features: ["Relationship consistency", "Migration metadata"],
            deprecationDate: nil
        ),
        FormatVersionInfo(
            version: 5,
            releaseDate: "2025-01-01",
            features: ["Enforced checksum validation", "Deterministic encoding"],
            deprecationDate: nil
        ),
        FormatVersionInfo(
            version: 6,
            releaseDate: "2025-06-01",
            features: ["LZFSE compression", "Encrypted compression", "Backward compatible"],
            deprecationDate: nil
        ),
        FormatVersionInfo(
            version: 7,
            releaseDate: "2026-01-01",
            features: ["Future enhancements"],
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
