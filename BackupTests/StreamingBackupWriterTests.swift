import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("StreamingBackupWriter Tests")
struct StreamingBackupWriterTests {
    
    @Test("Streaming export creates valid backup")
    func testStreamingExportCreatesValidBackup() async throws {
        // Given
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create test data
        try createTestStudents(in: context, count: 100)
        
        let writer = StreamingBackupWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".backup")
        
        var progressCalls = 0
        
        // When
        let summary = try await writer.streamingExport(
            modelContext: context,
            to: tempURL,
            password: nil
        ) { progress, phase, count, error in
            progressCalls += 1
            #expect(progress >= 0.0 && progress <= 1.0)
            #expect(count >= 0)
        }
        
        // Then
        #expect(summary.totalEntityCount == 100)
        #expect(summary.entityTypeCounts["Student"] == 100)
        #expect(summary.success == true)
        #expect(progressCalls > 0)
        #expect(FileManager.default.fileExists(atPath: tempURL.path))
        
        // Verify the backup can be decoded
        let data = try Data(contentsOf: tempURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        
        #expect(payload.metadata.totalEntityCount == 100)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    @Test("Streaming export handles large datasets")
    func testStreamingExportHandlesLargeDatasets() async throws {
        // Given
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create a large dataset
        try createTestStudents(in: context, count: 1000)
        
        let writer = StreamingBackupWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".backup")
        
        // When
        let summary = try await writer.streamingExport(
            modelContext: context,
            to: tempURL,
            password: nil
        ) { _, _, _, _ in }
        
        // Then
        #expect(summary.totalEntityCount == 1000)
        #expect(summary.success == true)
        #expect(summary.durationSeconds > 0)
        
        // Verify file size is reasonable
        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = attributes[.size] as! Int64
        #expect(fileSize > 0)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    @Test("Streaming export with password encrypts data")
    func testStreamingExportWithPasswordEncrypts() async throws {
        // Given
        let container = try createTestContainer()
        let context = ModelContext(container)
        try createTestStudents(in: context, count: 10)
        
        let writer = StreamingBackupWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".backup")
        let password = "testPassword123"
        
        // When
        let summary = try await writer.streamingExport(
            modelContext: context,
            to: tempURL,
            password: password
        ) { _, _, _, _ in }
        
        // Then
        #expect(summary.success == true)
        
        // Verify data is encrypted (can't be decoded without password)
        let data = try Data(contentsOf: tempURL)
        let decoder = JSONDecoder()
        
        // Should throw because data is encrypted
        #expect(throws: Error.self) {
            try decoder.decode(BackupPayload.self, from: data)
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    @Test("Streaming export reports progress correctly")
    func testStreamingExportReportsProgress() async throws {
        // Given
        let container = try createTestContainer()
        let context = ModelContext(container)
        try createTestStudents(in: context, count: 50)
        
        let writer = StreamingBackupWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".backup")
        
        var lastProgress: Double = 0.0
        var progressIsMonotonic = true
        
        // When
        _ = try await writer.streamingExport(
            modelContext: context,
            to: tempURL,
            password: nil
        ) { progress, phase, count, error in
            if progress < lastProgress {
                progressIsMonotonic = false
            }
            lastProgress = progress
        }
        
        // Then
        #expect(progressIsMonotonic == true)
        #expect(lastProgress == 1.0)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    @Test("Streaming export handles errors gracefully")
    func testStreamingExportHandlesErrors() async throws {
        // Given
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let writer = StreamingBackupWriter()
        // Use invalid URL
        let invalidURL = URL(fileURLWithPath: "/invalid/path/that/does/not/exist/backup.backup")
        
        // When/Then
        await #expect(throws: Error.self) {
            try await writer.streamingExport(
                modelContext: context,
                to: invalidURL,
                password: nil
            ) { _, _, _, _ in }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Student.self,
            configurations: config
        )
    }
    
    private func createTestStudents(in context: ModelContext, count: Int) throws {
        for i in 0..<count {
            let student = Student(
                firstName: "Student",
                lastName: "\(i)",
                grade: Grade.allCases.randomElement()!
            )
            context.insert(student)
        }
        try context.save()
    }
}
