//
//  BackupRestoreFlowTests.swift
//  Maria's Notebook
//
//  Phase 5 Week 3: Integration Tests
//  Target: 6 tests for Backup/Restore flow
//

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("Integration: Backup and Restore Flow")
@MainActor
struct BackupRestoreFlowTests {
    
    // MARK: - Test Helpers
    
    private func seedTestData(context: ModelContext) throws -> (students: [Student], lessons: [Lesson], work: [WorkModel]) {
        // Create students
        let student1 = Student(name: "Alice Johnson")
        let student2 = Student(name: "Bob Smith")
        let student3 = Student(name: "Carol Davis")
        
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)
        
        // Create lessons
        let lesson1 = Lesson(
            name: "Introduction to Algebra",
            lessonType: "Standard",
            subject: "Mathematics",
            subheading: "Basic Concepts",
            description: "Introduction to algebraic thinking",
            body: "Lesson content here",
            materials: "Textbook Chapter 1",
            group: "Algebra I"
        )
        
        let lesson2 = Lesson(
            name: "Cell Biology",
            lessonType: "Standard",
            subject: "Science",
            subheading: "Cellular Structure",
            description: "Study of cell structure and function",
            body: "Lesson content here",
            materials: "Lab Manual Pages 10-20",
            group: "Biology 101"
        )
        
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()
        
        // Create work items
        let work1 = WorkModel(
            title: "Algebra Practice Set 1",
            studentID: student1.id.uuidString,
            lessonID: lesson1.id.uuidString,
            kind: .practiceLesson,
            status: .active
        )
        
        let work2 = WorkModel(
            title: "Cell Diagram Assignment",
            studentID: student2.id.uuidString,
            lessonID: lesson2.id.uuidString,
            kind: .practiceLesson,
            status: .complete
        )
        work2.completedAt = Date()
        work2.completionOutcome = .mastered
        
        context.insert(work1)
        context.insert(work2)
        try context.save()
        
        return ([student1, student2, student3], [lesson1, lesson2], [work1, work2])
    }
    
    // MARK: - GenericBackupContainer Tests
    
    @Test("Complete flow: Backup container creation")
    func backupContainerCreation() async throws {
        // Given: Empty backup container
        var container = GenericBackupContainer()
        
        // Then: Container initialized with defaults
        #expect(container.version == 2)
        #expect(container.compatibleVersions == 1...2)
        #expect(container.entities.isEmpty)
        #expect(!container.appVersion.isEmpty)
        
        // When: Adding test data
        struct TestData: BackupEncodable {
            static var entityName: String { "TestData" }
            var id: UUID
            var name: String
        }
        
        let testItems = [
            TestData(id: UUID(), name: "Item 1"),
            TestData(id: UUID(), name: "Item 2")
        ]
        
        try container.add(testItems)
        
        // Then: Data added to container
        #expect(container.entities["TestData"] != nil)
        #expect(container.entities["TestData"]?.count == 2)
        #expect(container.metadata.entityCounts["TestData"] == 2)
    }
    
    @Test("Complete flow: Backup and restore round-trip")
    func backupAndRestoreRoundTrip() async throws {
        // Given: Test entity type
        struct BackupableEntity: BackupEncodable {
            static var entityName: String { "BackupableEntity" }
            var id: UUID
            var name: String
            var value: Int
            var createdAt: Date
        }
        
        // When: Creating backup with data
        var container = GenericBackupContainer()
        
        let originalData = [
            BackupableEntity(id: UUID(), name: "Entity 1", value: 100, createdAt: Date()),
            BackupableEntity(id: UUID(), name: "Entity 2", value: 200, createdAt: Date()),
            BackupableEntity(id: UUID(), name: "Entity 3", value: 300, createdAt: Date())
        ]
        
        try container.add(originalData)
        
        // Then: Data can be restored
        let restoredData = try container.decode(BackupableEntity.self)
        
        #expect(restoredData.count == 3)
        #expect(restoredData[0].name == "Entity 1")
        #expect(restoredData[0].value == 100)
        #expect(restoredData[1].name == "Entity 2")
        #expect(restoredData[1].value == 200)
        #expect(restoredData[2].name == "Entity 3")
        #expect(restoredData[2].value == 300)
    }
    
    // MARK: - Size Estimation Tests
    
    @Test("Complete flow: Backup size estimation")
    func backupSizeEstimation() async throws {
        // Given: Container with test data
        struct SizeTestEntity: BackupEncodable {
            static var entityName: String { "SizeTestEntity" }
            var id: UUID
            var largeString: String
        }
        
        var container = GenericBackupContainer()
        
        // Add entities with varying sizes
        let smallEntity = SizeTestEntity(id: UUID(), largeString: "Small")
        let largeEntity = SizeTestEntity(id: UUID(), largeString: String(repeating: "X", count: 10000))
        
        try container.add([smallEntity, largeEntity])
        
        // When: Estimating size
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(container)
        container.metadata.totalSize = Int64(encoded.count)
        
        // Then: Size is reasonable
        #expect(container.metadata.totalSize > 0)
        #expect(container.metadata.totalSize > 10000) // At least the size of large string
    }
    
    // MARK: - Version Compatibility Tests
    
    @Test("Complete flow: Version compatibility checking")
    func versionCompatibilityChecking() async throws {
        // Given: Containers with different versions
        var currentVersionContainer = GenericBackupContainer()
        currentVersionContainer.version = 2
        currentVersionContainer.compatibleVersions = 1...2
        
        var futureVersionContainer = GenericBackupContainer()
        futureVersionContainer.version = 5
        futureVersionContainer.compatibleVersions = 5...10
        
        var oldVersionContainer = GenericBackupContainer()
        oldVersionContainer.version = 1
        oldVersionContainer.compatibleVersions = 1...1
        
        // Then: Compatibility checks work correctly
        #expect(currentVersionContainer.isCompatible() == true)
        #expect(futureVersionContainer.isCompatible() == false)
        #expect(oldVersionContainer.isCompatible() == true) // v1 is compatible with current v2
    }
    
    // MARK: - Metadata Tests
    
    @Test("Complete flow: Backup metadata tracking")
    func backupMetadataTracking() async throws {
        // Given: Container with multiple entity types
        struct EntityTypeA: BackupEncodable {
            static var entityName: String { "EntityTypeA" }
            var id: UUID
        }
        
        struct EntityTypeB: BackupEncodable {
            static var entityName: String { "EntityTypeB" }
            var id: UUID
            var name: String
        }
        
        var container = GenericBackupContainer()
        
        // When: Adding different entity types
        let entitiesA = [
            EntityTypeA(id: UUID()),
            EntityTypeA(id: UUID()),
            EntityTypeA(id: UUID())
        ]
        
        let entitiesB = [
            EntityTypeB(id: UUID(), name: "B1"),
            EntityTypeB(id: UUID(), name: "B2")
        ]
        
        try container.add(entitiesA)
        try container.add(entitiesB)
        
        // Then: Metadata tracks all entities
        #expect(container.metadata.entityCounts["EntityTypeA"] == 3)
        #expect(container.metadata.entityCounts["EntityTypeB"] == 2)
        #expect(container.metadata.entityCounts.count == 2)
        
        // And: Summary is generated
        let summary = container.metadata.summary
        #expect(summary.contains("EntityTypeA"))
        #expect(summary.contains("EntityTypeB"))
        #expect(summary.contains("3"))
        #expect(summary.contains("2"))
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Complete flow: Backup error handling")
    func backupErrorHandling() async throws {
        // Given: Incompatible version container
        var incompatibleContainer = GenericBackupContainer()
        incompatibleContainer.version = 99
        incompatibleContainer.compatibleVersions = 99...100
        
        // Then: Incompatibility detected
        #expect(incompatibleContainer.isCompatible() == false)
        
        // Given: Various backup errors
        let incompatibleError = BackupError.incompatibleVersion(backup: 99, app: 2)
        let notFoundError = BackupError.entityNotFound(name: "MissingEntity")
        
        // Then: Errors have descriptive messages
        #expect(incompatibleError.errorDescription?.contains("incompatible") == true)
        #expect(incompatibleError.errorDescription?.contains("99") == true)
        #expect(incompatibleError.errorDescription?.contains("2") == true)
        
        #expect(notFoundError.errorDescription?.contains("MissingEntity") == true)
    }
}

#endif
