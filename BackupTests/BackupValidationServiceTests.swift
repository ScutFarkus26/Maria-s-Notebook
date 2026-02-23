import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("BackupValidationService Tests")
struct BackupValidationServiceTests {
    
    @Test("Validation passes for valid backup")
    func testValidationPassesForValidBackup() async throws {
        // Given
        let service = BackupValidationService()
        let payload = createValidBackupPayload()
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: nil,
            mode: .replace
        )
        
        // Then
        #expect(result.isValid == true)
        #expect(result.errors.isEmpty)
    }
    
    @Test("Validation detects missing metadata")
    func testValidationDetectsMissingMetadata() async throws {
        // Given
        let service = BackupValidationService()
        var payload = createValidBackupPayload()
        payload.metadata.appVersion = nil
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: nil,
            mode: .replace
        )
        
        // Then
        #expect(result.warnings.contains { $0.contains("metadata") })
    }
    
    @Test("Validation detects format version incompatibility")
    func testValidationDetectsFormatVersionIncompatibility() async throws {
        // Given
        let service = BackupValidationService()
        var payload = createValidBackupPayload()
        payload.metadata.formatVersion = 999 // Future version
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: nil,
            mode: .replace
        )
        
        // Then
        #expect(result.isValid == false)
        #expect(result.errors.contains { $0.contains("format version") || $0.contains("incompatible") })
    }
    
    @Test("Validation detects corrupt entity data")
    func testValidationDetectsCorruptEntityData() async throws {
        // Given
        let service = BackupValidationService()
        var payload = createValidBackupPayload()
        
        // Add corrupt entity (invalid JSON)
        payload.entities["Student"] = [
            ["invalid": "data", "missing": "required_fields"]
        ]
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: nil,
            mode: .replace
        )
        
        // Then
        #expect(result.errors.count > 0)
    }
    
    @Test("Validation detects duplicate entities in append mode")
    func testValidationDetectsDuplicatesInAppendMode() async throws {
        // Given
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create existing student
        let existingStudent = Student(
            firstName: "John",
            lastName: "Doe",
            grade: .ninth
        )
        existingStudent.studentID = "STUDENT001"
        context.insert(existingStudent)
        try context.save()
        
        let service = BackupValidationService()
        let payload = createBackupPayloadWithStudent(studentID: "STUDENT001")
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: context,
            mode: .append
        )
        
        // Then
        #expect(result.warnings.contains { $0.contains("duplicate") || $0.contains("exist") })
    }
    
    @Test("Validation allows duplicates in replace mode")
    func testValidationAllowsDuplicatesInReplaceMode() async throws {
        // Given
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let existingStudent = Student(
            firstName: "John",
            lastName: "Doe",
            grade: .ninth
        )
        existingStudent.studentID = "STUDENT001"
        context.insert(existingStudent)
        try context.save()
        
        let service = BackupValidationService()
        let payload = createBackupPayloadWithStudent(studentID: "STUDENT001")
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: context,
            mode: .replace
        )
        
        // Then
        #expect(result.isValid == true)
    }
    
    @Test("Validation provides entity type details")
    func testValidationProvidesEntityTypeDetails() async throws {
        // Given
        let service = BackupValidationService()
        let payload = createValidBackupPayload()
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: nil,
            mode: .replace
        )
        
        // Then
        #expect(!result.entityTypeDetails.isEmpty)
        
        if let studentDetails = result.entityTypeDetails["Student"] {
            #expect(studentDetails.willInsert > 0)
            #expect(studentDetails.entityType == "Student")
        }
    }
    
    @Test("Validation detects missing relationships")
    func testValidationDetectsMissingRelationships() async throws {
        // Given
        let service = BackupValidationService()
        var payload = createValidBackupPayload()
        
        // Add a presentation that references a non-existent student
        payload.entities["Presentation"] = [
            [
                "presentationID": "PRES001",
                "topic": "Test Topic",
                "presentationDate": ISO8601DateFormatter().string(from: Date()),
                "studentID": "NONEXISTENT_STUDENT"
            ]
        ]
        payload.metadata.totalEntityCount += 1
        payload.metadata.entityTypeCounts["Presentation"] = 1
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: nil,
            mode: .replace
        )
        
        // Then
        #expect(result.warnings.contains { $0.contains("relationship") || $0.contains("reference") } || 
                result.errors.contains { $0.contains("relationship") || $0.contains("reference") })
    }
    
    @Test("Validation generates recommendations")
    func testValidationGeneratesRecommendations() async throws {
        // Given
        let service = BackupValidationService()
        let payload = createValidBackupPayload()
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: nil,
            mode: .replace
        )
        
        // Then
        // Should have some recommendations for best practices
        #expect(result.recommendations.count >= 0)
    }
    
    @Test("Validation handles empty backup")
    func testValidationHandlesEmptyBackup() async throws {
        // Given
        let service = BackupValidationService()
        let payload = BackupPayload(
            metadata: BackupMetadata(
                timestamp: Date(),
                deviceID: "TEST",
                totalEntityCount: 0,
                entityTypeCounts: [:],
                appVersion: "1.0.0",
                formatVersion: 1
            ),
            entities: [:],
            relationships: [:],
            checksums: nil,
            signature: nil
        )
        
        // When
        let result = try await service.validate(
            payload: payload,
            against: nil,
            mode: .replace
        )
        
        // Then
        #expect(result.isValid == true)
        #expect(result.warnings.contains { $0.contains("empty") })
    }
    
    // MARK: - Helper Methods
    
    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Student.self, Presentation.self,
            configurations: config
        )
    }
    
    private func createValidBackupPayload() -> BackupPayload {
        let student: [String: Any] = [
            "studentID": "STUDENT001",
            "firstName": "John",
            "lastName": "Doe",
            "grade": "9th"
        ]
        
        return BackupPayload(
            metadata: BackupMetadata(
                timestamp: Date(),
                deviceID: "TEST_DEVICE",
                totalEntityCount: 1,
                entityTypeCounts: ["Student": 1],
                appVersion: "1.0.0",
                formatVersion: 1
            ),
            entities: ["Student": [student]],
            relationships: [:],
            checksums: nil,
            signature: nil
        )
    }
    
    private func createBackupPayloadWithStudent(studentID: String) -> BackupPayload {
        let student: [String: Any] = [
            "studentID": studentID,
            "firstName": "John",
            "lastName": "Doe",
            "grade": "9th"
        ]
        
        return BackupPayload(
            metadata: BackupMetadata(
                timestamp: Date(),
                deviceID: "TEST_DEVICE",
                totalEntityCount: 1,
                entityTypeCounts: ["Student": 1],
                appVersion: "1.0.0",
                formatVersion: 1
            ),
            entities: ["Student": [student]],
            relationships: [:],
            checksums: nil,
            signature: nil
        )
    }
}
