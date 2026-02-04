//
//  GenericBackupCodecTests.swift
//  Maria's Notebook
//
//  Phase 5 Week 1: Backup Infrastructure Tests
//  Target: 12 tests for GenericBackupCodec
//

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("GenericBackupCodec Tests")
@MainActor
struct GenericBackupCodecTests {
    
    // MARK: - Test Model
    
    /// Test entity that conforms to BackupEncodable for testing
    struct TestEntity: BackupEncodable {
        static var entityName: String { "TestEntity" }
        var backupVersion: Int { 1 }
        
        var id: UUID
        var name: String
        var value: Int
        var createdAt: Date
    }
    
    struct AnotherTestEntity: BackupEncodable {
        static var entityName: String { "AnotherTestEntity" }
        var backupVersion: Int { 1 }
        
        var id: UUID
        var title: String
        var count: Int
    }
    
    // MARK: - Container Creation Tests
    
    @Test("GenericBackupContainer initializes with defaults")
    func containerInitializesWithDefaults() {
        // When: Creating a new container
        let container = GenericBackupContainer()
        
        // Then: Default values set
        #expect(container.version == 2)
        #expect(container.compatibleVersions == 1...2)
        #expect(container.entities.isEmpty)
        #expect(container.metadata.entityCounts.isEmpty)
        #expect(container.metadata.encrypted == false)
    }
    
    @Test("GenericBackupContainer stores creation timestamp")
    func containerStoresCreationTimestamp() {
        // When: Creating a container
        let beforeCreation = Date()
        let container = GenericBackupContainer()
        let afterCreation = Date()
        
        // Then: Timestamp is within expected range
        #expect(container.createdAt >= beforeCreation)
        #expect(container.createdAt <= afterCreation)
    }
    
    @Test("GenericBackupContainer stores app version")
    func containerStoresAppVersion() {
        // When: Creating a container
        let container = GenericBackupContainer()
        
        // Then: App version captured
        #expect(!container.appVersion.isEmpty)
    }
    
    // MARK: - Entity Encoding Tests
    
    @Test("Container add() encodes entities correctly")
    func containerAddEncodesEntities() throws {
        // Given: Test entities
        var container = GenericBackupContainer()
        let entities = [
            TestEntity(id: UUID(), name: "Entity 1", value: 100, createdAt: Date()),
            TestEntity(id: UUID(), name: "Entity 2", value: 200, createdAt: Date())
        ]
        
        // When: Adding entities to container
        try container.add(entities)
        
        // Then: Entities stored as encoded data
        #expect(container.entities["TestEntity"] != nil)
        #expect(container.entities["TestEntity"]?.count == 2)
        #expect(container.metadata.entityCounts["TestEntity"] == 2)
    }
    
    @Test("Container add() handles multiple entity types")
    func containerAddHandlesMultipleEntityTypes() throws {
        // Given: Different entity types
        var container = GenericBackupContainer()
        
        let testEntities = [
            TestEntity(id: UUID(), name: "Test", value: 1, createdAt: Date())
        ]
        let anotherEntities = [
            AnotherTestEntity(id: UUID(), title: "Another", count: 42),
            AnotherTestEntity(id: UUID(), title: "More", count: 99)
        ]
        
        // When: Adding both types
        try container.add(testEntities)
        try container.add(anotherEntities)
        
        // Then: Both types stored separately
        #expect(container.entities.keys.count == 2)
        #expect(container.entities["TestEntity"]?.count == 1)
        #expect(container.entities["AnotherTestEntity"]?.count == 2)
        #expect(container.metadata.entityCounts["TestEntity"] == 1)
        #expect(container.metadata.entityCounts["AnotherTestEntity"] == 2)
    }
    
    @Test("Container add() overwrites existing entities of same type")
    func containerAddOverwritesExistingEntities() throws {
        // Given: Container with entities
        var container = GenericBackupContainer()
        let firstBatch = [
            TestEntity(id: UUID(), name: "First", value: 1, createdAt: Date())
        ]
        try container.add(firstBatch)
        
        // When: Adding new batch of same type
        let secondBatch = [
            TestEntity(id: UUID(), name: "Second", value: 2, createdAt: Date()),
            TestEntity(id: UUID(), name: "Third", value: 3, createdAt: Date())
        ]
        try container.add(secondBatch)
        
        // Then: Second batch replaces first
        #expect(container.entities["TestEntity"]?.count == 2)
        #expect(container.metadata.entityCounts["TestEntity"] == 2)
    }
    
    // MARK: - Entity Decoding Tests
    
    @Test("Container decode() retrieves entities correctly")
    func containerDecodeRetrievesEntities() throws {
        // Given: Container with encoded entities
        var container = GenericBackupContainer()
        let originalEntities = [
            TestEntity(id: UUID(), name: "Entity A", value: 111, createdAt: Date()),
            TestEntity(id: UUID(), name: "Entity B", value: 222, createdAt: Date())
        ]
        try container.add(originalEntities)
        
        // When: Decoding entities
        let decodedEntities = try container.decode(TestEntity.self)
        
        // Then: Entities match originals
        #expect(decodedEntities.count == 2)
        #expect(decodedEntities[0].name == "Entity A")
        #expect(decodedEntities[0].value == 111)
        #expect(decodedEntities[1].name == "Entity B")
        #expect(decodedEntities[1].value == 222)
    }
    
    @Test("Container decode() returns empty array for non-existent type")
    func containerDecodeReturnsEmptyForNonExistent() throws {
        // Given: Empty container
        let container = GenericBackupContainer()
        
        // When: Decoding non-existent type
        let entities = try container.decode(TestEntity.self)
        
        // Then: Empty array returned
        #expect(entities.isEmpty)
    }
    
    @Test("Container decode() handles dates correctly")
    func containerDecodeHandlesDatesCorrectly() throws {
        // Given: Entity with specific date
        var container = GenericBackupContainer()
        let specificDate = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let originalEntity = TestEntity(id: UUID(), name: "DateTest", value: 999, createdAt: specificDate)
        try container.add([originalEntity])
        
        // When: Decoding
        let decodedEntities = try container.decode(TestEntity.self)
        
        // Then: Date preserved (within 1 second tolerance for encoding precision)
        #expect(decodedEntities.count == 1)
        let timeDifference = abs(decodedEntities[0].createdAt.timeIntervalSince(specificDate))
        #expect(timeDifference < 1.0)
    }
    
    // MARK: - Round-Trip Encoding Tests
    
    @Test("Entity encoding and decoding is lossless")
    func entityEncodingDecodingIsLossless() throws {
        // Given: Entity with all fields populated
        var container = GenericBackupContainer()
        let id = UUID()
        let date = Date()
        let original = TestEntity(id: id, name: "Test Entity", value: 42, createdAt: date)
        
        // When: Encoding and decoding
        try container.add([original])
        let decoded = try container.decode(TestEntity.self)
        
        // Then: All fields match
        #expect(decoded.count == 1)
        #expect(decoded[0].id == id)
        #expect(decoded[0].name == "Test Entity")
        #expect(decoded[0].value == 42)
        // Date comparison with small tolerance
        #expect(abs(decoded[0].createdAt.timeIntervalSince(date)) < 1.0)
    }
    
    @Test("Multiple entity types round-trip independently")
    func multipleEntityTypesRoundTripIndependently() throws {
        // Given: Container with multiple entity types
        var container = GenericBackupContainer()
        
        let testEntity = TestEntity(id: UUID(), name: "Test", value: 100, createdAt: Date())
        let anotherEntity = AnotherTestEntity(id: UUID(), title: "Another", count: 50)
        
        try container.add([testEntity])
        try container.add([anotherEntity])
        
        // When: Decoding each type
        let decodedTest = try container.decode(TestEntity.self)
        let decodedAnother = try container.decode(AnotherTestEntity.self)
        
        // Then: Each type decoded correctly
        #expect(decodedTest.count == 1)
        #expect(decodedTest[0].name == "Test")
        #expect(decodedTest[0].value == 100)
        
        #expect(decodedAnother.count == 1)
        #expect(decodedAnother[0].title == "Another")
        #expect(decodedAnother[0].count == 50)
    }
    
    // MARK: - Version Compatibility Tests
    
    @Test("Container reports compatibility correctly")
    func containerReportsCompatibilityCorrectly() {
        // Given: Containers with different versions
        var compatibleContainer = GenericBackupContainer()
        compatibleContainer.version = 2
        compatibleContainer.compatibleVersions = 1...2
        
        var incompatibleContainer = GenericBackupContainer()
        incompatibleContainer.version = 5
        incompatibleContainer.compatibleVersions = 5...10
        
        // Then: Compatibility checks work
        #expect(compatibleContainer.isCompatible() == true)
        #expect(incompatibleContainer.isCompatible() == false)
    }
    
    // MARK: - Metadata Tests
    
    @Test("Metadata tracks entity counts correctly")
    func metadataTracksEntityCountsCorrectly() throws {
        // Given: Container with multiple entity batches
        var container = GenericBackupContainer()
        
        try container.add([
            TestEntity(id: UUID(), name: "E1", value: 1, createdAt: Date()),
            TestEntity(id: UUID(), name: "E2", value: 2, createdAt: Date()),
            TestEntity(id: UUID(), name: "E3", value: 3, createdAt: Date())
        ])
        
        try container.add([
            AnotherTestEntity(id: UUID(), title: "A1", count: 10),
            AnotherTestEntity(id: UUID(), title: "A2", count: 20)
        ])
        
        // Then: Metadata reflects correct counts
        #expect(container.metadata.entityCounts["TestEntity"] == 3)
        #expect(container.metadata.entityCounts["AnotherTestEntity"] == 2)
    }
    
    @Test("Metadata summary provides readable output")
    func metadataSummaryProvidesReadableOutput() throws {
        // Given: Container with data
        var container = GenericBackupContainer()
        try container.add([
            TestEntity(id: UUID(), name: "Test", value: 1, createdAt: Date())
        ])
        container.metadata.totalSize = 1024
        container.metadata.encrypted = true
        container.metadata.compressionRatio = 0.75
        
        // When: Getting summary
        let summary = container.metadata.summary
        
        // Then: Summary contains key information
        #expect(summary.contains("TestEntity"))
        #expect(summary.contains("1"))
        #expect(summary.contains("Encrypted: Yes"))
    }
    
    // MARK: - BackupEncodable Protocol Tests
    
    @Test("BackupEncodable provides default backupVersion")
    func backupEncodableDefaultVersion() {
        // Given: Entity using default version
        struct DefaultVersionEntity: BackupEncodable {
            static var entityName: String { "DefaultVersionEntity" }
            var id: UUID
        }
        
        let entity = DefaultVersionEntity(id: UUID())
        
        // Then: Default version is 1
        #expect(entity.backupVersion == 1)
    }
    
    @Test("BackupEncodable allows custom backupVersion")
    func backupEncodableCustomVersion() {
        // Given: Entity with custom version
        struct CustomVersionEntity: BackupEncodable {
            static var entityName: String { "CustomVersionEntity" }
            var backupVersion: Int { 5 }
            var id: UUID
        }
        
        let entity = CustomVersionEntity(id: UUID())
        
        // Then: Custom version used
        #expect(entity.backupVersion == 5)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("BackupError provides descriptive messages")
    func backupErrorDescriptiveMessages() {
        // Given: Various error types
        let incompatibleError = BackupError.incompatibleVersion(backup: 3, app: 2)
        let notFoundError = BackupError.entityNotFound(name: "Student")
        let decodingError = BackupError.decodingFailed(entityName: "WorkModel", error: NSError(domain: "test", code: 1))
        
        // Then: Errors have descriptions
        #expect(incompatibleError.errorDescription?.contains("incompatible") == true)
        #expect(incompatibleError.errorDescription?.contains("3") == true)
        #expect(incompatibleError.errorDescription?.contains("2") == true)
        
        #expect(notFoundError.errorDescription?.contains("Student") == true)
        
        #expect(decodingError.errorDescription?.contains("WorkModel") == true)
    }
}

#endif
