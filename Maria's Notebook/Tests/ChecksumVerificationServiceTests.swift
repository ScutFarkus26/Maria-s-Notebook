import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("ChecksumVerificationService Tests")
struct ChecksumVerificationServiceTests {
    
    @Test("Generate checksum manifest creates valid checksums")
    func testGenerateChecksumManifestCreatesValidChecksums() throws {
        // Given
        let service = ChecksumVerificationService()
        let payload = createTestPayload()
        
        // When
        let manifest = try service.generateChecksumManifest(for: payload)
        
        // Then
        #expect(manifest.entityTypeChecksums.count > 0)
        #expect(manifest.entityTypeChecksums["Student"] != nil)
        #expect(manifest.overallChecksum.count > 0)
        #expect(manifest.entityCount == payload.metadata.totalEntityCount)
    }
    
    @Test("Verification succeeds for matching checksums")
    func testVerificationSucceedsForMatchingChecksums() throws {
        // Given
        let service = ChecksumVerificationService()
        let payload = createTestPayload()
        let manifest = try service.generateChecksumManifest(for: payload)
        
        // When
        let result = try service.verify(payload: payload, against: manifest)
        
        // Then
        #expect(result.isValid == true)
        #expect(result.corruptedEntityTypes.isEmpty)
        #expect(result.missingEntityTypes.isEmpty)
    }
    
    @Test("Verification detects modified entities")
    func testVerificationDetectsModifiedEntities() throws {
        // Given
        let service = ChecksumVerificationService()
        var payload = createTestPayload()
        let manifest = try service.generateChecksumManifest(for: payload)
        
        // Modify the payload
        if var students = payload.entities["Student"] as? [[String: Any]] {
            students[0]["firstName"] = "Modified"
            payload.entities["Student"] = students
        }
        
        // When
        let result = try service.verify(payload: payload, against: manifest)
        
        // Then
        #expect(result.isValid == false)
        #expect(result.corruptedEntityTypes.contains("Student"))
    }
    
    @Test("Verification detects missing entity types")
    func testVerificationDetectsMissingEntityTypes() throws {
        // Given
        let service = ChecksumVerificationService()
        var payload = createTestPayload()
        let manifest = try service.generateChecksumManifest(for: payload)
        
        // Remove an entity type
        payload.entities.removeValue(forKey: "Student")
        
        // When
        let result = try service.verify(payload: payload, against: manifest)
        
        // Then
        #expect(result.isValid == false)
        #expect(result.missingEntityTypes.contains("Student"))
    }
    
    @Test("Verification detects added entity types")
    func testVerificationDetectsAddedEntityTypes() throws {
        // Given
        let service = ChecksumVerificationService()
        let payload = createTestPayload()
        let manifest = try service.generateChecksumManifest(for: payload)
        
        // Add a new entity type
        var modifiedPayload = payload
        modifiedPayload.entities["NewEntityType"] = [
            ["id": "NEW001", "name": "New Entity"]
        ]
        
        // When
        let result = try service.verify(payload: modifiedPayload, against: manifest)
        
        // Then
        #expect(result.isValid == false)
        #expect(result.extraEntityTypes.contains("NewEntityType"))
    }
    
    @Test("Verification detects overall corruption")
    func testVerificationDetectsOverallCorruption() throws {
        // Given
        let service = ChecksumVerificationService()
        var payload = createTestPayload()
        let manifest = try service.generateChecksumManifest(for: payload)
        
        // Modify metadata
        payload.metadata.totalEntityCount = 999
        
        // When
        let result = try service.verify(payload: payload, against: manifest)
        
        // Then
        #expect(result.isValid == false)
    }
    
    @Test("Checksum is deterministic")
    func testChecksumIsDeterministic() throws {
        // Given
        let service = ChecksumVerificationService()
        let payload = createTestPayload()
        
        // When
        let manifest1 = try service.generateChecksumManifest(for: payload)
        let manifest2 = try service.generateChecksumManifest(for: payload)
        
        // Then
        #expect(manifest1.overallChecksum == manifest2.overallChecksum)
        #expect(manifest1.entityTypeChecksums == manifest2.entityTypeChecksums)
    }
    
    @Test("Different payloads produce different checksums")
    func testDifferentPayloadsProduceDifferentChecksums() throws {
        // Given
        let service = ChecksumVerificationService()
        let payload1 = createTestPayload()
        var payload2 = createTestPayload()
        
        // Modify payload2
        if var students = payload2.entities["Student"] as? [[String: Any]] {
            students[0]["lastName"] = "Different"
            payload2.entities["Student"] = students
        }
        
        // When
        let manifest1 = try service.generateChecksumManifest(for: payload1)
        let manifest2 = try service.generateChecksumManifest(for: payload2)
        
        // Then
        #expect(manifest1.overallChecksum != manifest2.overallChecksum)
        #expect(manifest1.entityTypeChecksums["Student"] != manifest2.entityTypeChecksums["Student"])
    }
    
    @Test("Verification provides detailed error information")
    func testVerificationProvidesDetailedErrorInfo() throws {
        // Given
        let service = ChecksumVerificationService()
        var payload = createTestPayload()
        let manifest = try service.generateChecksumManifest(for: payload)
        
        // Corrupt multiple entity types
        payload.entities["Student"] = [["corrupted": "data"]]
        payload.entities["NewType"] = [["extra": "type"]]
        
        // When
        let result = try service.verify(payload: payload, against: manifest)
        
        // Then
        #expect(result.isValid == false)
        #expect(!result.corruptedEntityTypes.isEmpty)
        #expect(!result.extraEntityTypes.isEmpty)
    }
    
    @Test("Manifest includes timestamp")
    func testManifestIncludesTimestamp() throws {
        // Given
        let service = ChecksumVerificationService()
        let payload = createTestPayload()
        
        // When
        let manifest = try service.generateChecksumManifest(for: payload)
        
        // Then
        #expect(manifest.timestamp.timeIntervalSinceNow < 1.0)
        #expect(manifest.timestamp.timeIntervalSinceNow > -1.0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestPayload() -> BackupPayload {
        let students: [[String: Any]] = [
            [
                "studentID": "STUDENT001",
                "firstName": "John",
                "lastName": "Doe",
                "grade": "9th"
            ],
            [
                "studentID": "STUDENT002",
                "firstName": "Jane",
                "lastName": "Smith",
                "grade": "10th"
            ]
        ]
        
        return BackupPayload(
            metadata: BackupMetadata(
                timestamp: Date(),
                deviceID: "TEST_DEVICE",
                totalEntityCount: 2,
                entityTypeCounts: ["Student": 2],
                appVersion: "1.0.0",
                formatVersion: 1
            ),
            entities: ["Student": students],
            relationships: [:],
            checksums: nil,
            signature: nil
        )
    }
}
