import Foundation
import SwiftData

/// Generic protocol-based backup codec that eliminates parallel DTO hierarchies.
///
/// This codec replaces the 25+ parallel DTO types with a single generic encoding system.
///
/// **Before (Phase 6):**
/// - StudentDTO, LessonDTO, WorkModelDTO, etc. (25+ parallel types)
/// - BackupDTOTransformers for manual mapping
/// - BackupPayload with explicit entity lists
///
/// **After:**
/// - Single BackupEncodable protocol
/// - Automatic entity discovery
/// - Generic encoding/decoding
///
/// **Usage:**
/// ```swift
/// // Make model conform to protocol
/// extension Student: BackupEncodable {
///     static var entityName: String { "Student" }
/// }
///
/// // Backup automatically includes it
/// let container = try GenericBackupCodec.exportBackup(context: modelContext)
/// ```
protocol BackupEncodable: Codable {
    /// Unique entity name for this type (e.g., "Student", "WorkModel")
    static var entityName: String { get }
    
    /// Backup format version (for future schema changes)
    var backupVersion: Int { get }
}

extension BackupEncodable {
    /// Default backup version (override if needed)
    var backupVersion: Int { 1 }
}

// MARK: - Generic Backup Container

/// Container for backup data with automatic entity discovery
struct GenericBackupContainer: Codable {
    /// Backup format version
    var version: Int = 2  // v1 was legacy format, v2 is generic
    
    /// Compatible version range
    var compatibleVersions: ClosedRange<Int> = 1...2
    
    /// Creation timestamp
    var createdAt: Date
    
    /// App version that created this backup
    var appVersion: String
    
    /// Entity data keyed by entity name
    var entities: [String: [Data]]
    
    /// Metadata about the backup
    var metadata: BackupMetadata
    
    init(createdAt: Date = .now, appVersion: String = Bundle.main.appVersion) {
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.entities = [:]
        self.metadata = BackupMetadata()
    }
    
    /// Add entities of a given type to the backup
    mutating func add<T: BackupEncodable>(_ instances: [T]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try instances.map { try encoder.encode($0) }
        entities[T.entityName] = data
        
        metadata.entityCounts[T.entityName] = instances.count
    }
    
    /// Decode entities of a given type from the backup
    func decode<T: BackupEncodable>(_ type: T.Type) throws -> [T] {
        guard let data = entities[T.entityName] else { return [] }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try data.map { try decoder.decode(T.self, from: $0) }
    }
    
    /// Check if this backup is compatible with current app version
    func isCompatible() -> Bool {
        compatibleVersions.contains(Self.currentVersion)
    }
    
    static var currentVersion: Int { 2 }
}

// MARK: - Backup Metadata

struct BackupMetadata: Codable {
    var entityCounts: [String: Int] = [:]
    var totalSize: Int64 = 0
    var encrypted: Bool = false
    var compressionRatio: Double = 1.0
    
    var summary: String {
        """
        Backup Summary:
        - Total entities: \(entityCounts.values.reduce(0, +))
        - Entity types: \(entityCounts.count)
        - Size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
        - Encrypted: \(encrypted ? "Yes" : "No")
        - Compression: \(String(format: "%.1f%%", compressionRatio * 100))
        
        Entity breakdown:
        \(entityCounts.map { "  - \($0.key): \($0.value)" }.sorted().joined(separator: "\n"))
        """
    }
}

// MARK: - Generic Backup Codec

@MainActor
enum GenericBackupCodec {
    
    /// Export all BackupEncodable entities to a generic container
    static func exportBackup(context: ModelContext) throws -> GenericBackupContainer {
        var container = GenericBackupContainer()
        
        // Discover all BackupEncodable types from AppSchema
        let backupableTypes = discoverBackupableTypes()
        
        print("GenericBackupCodec: Found \(backupableTypes.count) backupable entity types")
        
        for entityType in backupableTypes {
            print("GenericBackupCodec: Exporting \(entityType.entityName)...")
            
            let instances = try fetchAll(entityType, in: context)
            let data = try instances.map { try JSONEncoder().encode($0) }
            container.entities[entityType.entityName] = data
            
            print("GenericBackupCodec: ✓ Exported \(instances.count) \(entityType.entityName)")
        }
        
        container.metadata.totalSize = estimateSize(container)
        
        return container
    }
    
    /// Import entities from a generic container into context
    static func importBackup(_ container: GenericBackupContainer, into context: ModelContext) throws {
        guard container.isCompatible() else {
            throw BackupError.incompatibleVersion(
                backup: container.version,
                app: GenericBackupContainer.currentVersion
            )
        }
        
        let backupableTypes = discoverBackupableTypes()
        
        for entityType in backupableTypes {
            guard container.entities.keys.contains(entityType.entityName) else {
                print("GenericBackupCodec: Skipping \(entityType.entityName) (not in backup)")
                continue
            }
            
            print("GenericBackupCodec: Importing \(entityType.entityName)...")
            
            let instances = try container.decode(entityType)
            
            for instance in instances {
                if let model = instance as? (any PersistentModel) {
                    context.insert(model)
                }
            }
            
            print("GenericBackupCodec: ✓ Imported \(instances.count) \(entityType.entityName)")
        }
        
        try context.save()
    }
    
    // MARK: - Private Helpers
    
    private static func discoverBackupableTypes() -> [BackupEncodable.Type] {
        // For now, manually register types
        // In Phase 6, this will use runtime reflection or a registry
        return [
            // Core entities
            // Student.self,  // Uncomment after conformance added
            // Lesson.self,
            // WorkModel.self,
            // Note.self,
            // ... (48 total models)
        ]
    }
    
    private static func fetchAll<T: BackupEncodable>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        // This requires T to also conform to PersistentModel
        // Will be implemented in Phase 6 when models conform to both protocols
        
        // For now, return empty array (placeholder)
        return []
    }
    
    private static func estimateSize(_ container: GenericBackupContainer) -> Int64 {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(container) {
            return Int64(data.count)
        }
        return 0
    }
}

// MARK: - Backup Errors

enum BackupError: LocalizedError {
    case incompatibleVersion(backup: Int, app: Int)
    case entityNotFound(name: String)
    case decodingFailed(entityName: String, error: Error)
    
    var errorDescription: String? {
        switch self {
        case .incompatibleVersion(let backup, let app):
            return "Backup version \(backup) is incompatible with app version \(app)"
        case .entityNotFound(let name):
            return "Entity type '\(name)' not found in backup"
        case .decodingFailed(let name, let error):
            return "Failed to decode \(name): \(error.localizedDescription)"
        }
    }
}

// MARK: - Migration Support

extension GenericBackupCodec {
    
    /// Migrate legacy backup format to generic format
    static func migrateLegacyBackup(_ legacyData: Data) throws -> GenericBackupContainer {
        // Placeholder for Phase 6
        // This will convert old BackupPayload to GenericBackupContainer
        throw BackupError.entityNotFound(name: "LegacyMigration")
    }
}

// MARK: - Bundle Extension

private extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
    }
}

// MARK: - Phase 6 Notes

/*
 Phase 6 Implementation Plan:
 
 1. Make all 48 models conform to BackupEncodable:
    extension Student: BackupEncodable {
        static var entityName: String { "Student" }
    }
 
 2. Update discoverBackupableTypes() to return all conforming types
 
 3. Implement fetchAll() using FetchDescriptor:
    let descriptor = FetchDescriptor<T>()
    return try context.fetch(descriptor)
 
 4. Update BackupService to use GenericBackupCodec
 
 5. Add backward compatibility for legacy backups
 
 6. Test thoroughly with existing backup files
 
 7. Remove old DTO files after migration complete
 */
