import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("DeltaSyncService Tests")
struct DeltaSyncServiceTests {
    
    @Test("Generate delta for identical files produces no chunks")
    func testGenerateDeltaForIdenticalFiles() async throws {
        // Given
        let service = DeltaSyncService()
        let data = createTestBackupData(size: 1024)
        let baseURL = try createTemporaryFile(with: data)
        let targetURL = try createTemporaryFile(with: data)
        
        // When
        let manifest = try await service.generateDelta(from: baseURL, to: targetURL)
        
        // Then
        #expect(manifest.chunks.isEmpty)
        #expect(manifest.baseSize == data.count)
        #expect(manifest.targetSize == data.count)
        
        // Cleanup
        try? FileManager.default.removeItem(at: baseURL)
        try? FileManager.default.removeItem(at: targetURL)
    }
    
    @Test("Generate delta for different files produces chunks")
    func testGenerateDeltaForDifferentFiles() async throws {
        // Given
        let service = DeltaSyncService()
        let baseData = createTestBackupData(size: 1024)
        let targetData = createTestBackupData(size: 2048, seed: 42)
        let baseURL = try createTemporaryFile(with: baseData)
        let targetURL = try createTemporaryFile(with: targetData)
        
        // When
        let manifest = try await service.generateDelta(from: baseURL, to: targetURL)
        
        // Then
        #expect(!manifest.chunks.isEmpty)
        #expect(manifest.baseSize == baseData.count)
        #expect(manifest.targetSize == targetData.count)
        
        // Cleanup
        try? FileManager.default.removeItem(at: baseURL)
        try? FileManager.default.removeItem(at: targetURL)
    }
    
    @Test("Apply delta reconstructs target file")
    func testApplyDeltaReconstructsTargetFile() async throws {
        // Given
        let service = DeltaSyncService()
        let baseData = createTestBackupData(size: 1024)
        let targetData = createTestBackupData(size: 2048, seed: 42)
        let baseURL = try createTemporaryFile(with: baseData)
        let targetURL = try createTemporaryFile(with: targetData)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        // Generate delta
        let manifest = try await service.generateDelta(from: baseURL, to: targetURL)
        
        // When
        try await service.applyDelta(manifest: manifest, to: baseURL, outputURL: outputURL)
        
        // Then
        let reconstructedData = try Data(contentsOf: outputURL)
        #expect(reconstructedData == targetData)
        
        // Cleanup
        try? FileManager.default.removeItem(at: baseURL)
        try? FileManager.default.removeItem(at: targetURL)
        try? FileManager.default.removeItem(at: outputURL)
    }
    
    @Test("Delta sync reduces upload size for similar files")
    func testDeltaSyncReducesUploadSize() async throws {
        // Given
        let service = DeltaSyncService()
        
        // Create base backup
        var basePayload = createTestPayload(studentCount: 100)
        let baseData = try JSONEncoder().encode(basePayload)
        let baseURL = try createTemporaryFile(with: baseData)
        
        // Create modified backup (add 10 new students)
        var targetPayload = basePayload
        for i in 100..<110 {
            let student: [String: Any] = [
                "studentID": "STUDENT\(String(format: "%03d", i))",
                "firstName": "Student",
                "lastName": "\(i)",
                "grade": "9th"
            ]
            if var students = targetPayload.entities["Student"] as? [[String: Any]] {
                students.append(student)
                targetPayload.entities["Student"] = students
            }
        }
        targetPayload.metadata.totalEntityCount += 10
        targetPayload.metadata.entityTypeCounts["Student"] = 110
        
        let targetData = try JSONEncoder().encode(targetPayload)
        let targetURL = try createTemporaryFile(with: targetData)
        
        // When
        let manifest = try await service.generateDelta(from: baseURL, to: targetURL)
        
        // Calculate delta size
        let deltaSize = manifest.chunks.reduce(0) { $0 + $1.data.count }
        
        // Then
        // Delta should be significantly smaller than full target
        #expect(deltaSize < targetData.count / 2)
        
        // Cleanup
        try? FileManager.default.removeItem(at: baseURL)
        try? FileManager.default.removeItem(at: targetURL)
    }
    
    @Test("Sync to cloud with no remote base uploads full file")
    func testSyncToCloudWithNoRemoteBase() async throws {
        // Given
        let service = DeltaSyncService()
        let data = createTestBackupData(size: 1024)
        let localURL = try createTemporaryFile(with: data)
        
        var uploadedChunks: [DeltaSyncService.DeltaChunk] = []
        var uploadProgress: [(Double, String)] = []
        
        // When
        let result = try await service.syncToCloud(
            localURL: localURL,
            remoteBaseURL: nil,
            uploadChunk: { chunk, index, total in
                uploadedChunks.append(chunk)
            },
            progress: { progress, message in
                uploadProgress.append((progress, message))
            }
        )
        
        // Then
        #expect(result.uploadedChunks > 0)
        #expect(result.totalBytes == data.count)
        #expect(!uploadedChunks.isEmpty)
        #expect(!uploadProgress.isEmpty)
        #expect(uploadProgress.last?.0 == 1.0)
        
        // Cleanup
        try? FileManager.default.removeItem(at: localURL)
    }
    
    @Test("Sync to cloud with remote base uploads delta")
    func testSyncToCloudWithRemoteBase() async throws {
        // Given
        let service = DeltaSyncService()
        let baseData = createTestBackupData(size: 1024)
        let localData = createTestBackupData(size: 2048, seed: 42)
        let baseURL = try createTemporaryFile(with: baseData)
        let localURL = try createTemporaryFile(with: localData)
        
        var uploadedChunks: [DeltaSyncService.DeltaChunk] = []
        
        // When
        let result = try await service.syncToCloud(
            localURL: localURL,
            remoteBaseURL: baseURL,
            uploadChunk: { chunk, index, total in
                uploadedChunks.append(chunk)
            },
            progress: { _, _ in }
        )
        
        // Then
        #expect(result.uploadedChunks > 0)
        #expect(!uploadedChunks.isEmpty)
        
        // Delta size should be less than full file
        let deltaSize = uploadedChunks.reduce(0) { $0 + $1.data.count }
        #expect(deltaSize < localData.count)
        
        // Cleanup
        try? FileManager.default.removeItem(at: baseURL)
        try? FileManager.default.removeItem(at: localURL)
    }
    
    @Test("Delta manifest is serializable")
    func testDeltaManifestIsSerializable() async throws {
        // Given
        let service = DeltaSyncService()
        let baseData = createTestBackupData(size: 1024)
        let targetData = createTestBackupData(size: 2048, seed: 42)
        let baseURL = try createTemporaryFile(with: baseData)
        let targetURL = try createTemporaryFile(with: targetData)
        
        let manifest = try await service.generateDelta(from: baseURL, to: targetURL)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(manifest)
        
        let decoder = JSONDecoder()
        let decodedManifest = try decoder.decode(DeltaSyncService.DeltaManifest.self, from: data)
        
        // Then
        #expect(decodedManifest.chunks.count == manifest.chunks.count)
        #expect(decodedManifest.baseSize == manifest.baseSize)
        #expect(decodedManifest.targetSize == manifest.targetSize)
        
        // Cleanup
        try? FileManager.default.removeItem(at: baseURL)
        try? FileManager.default.removeItem(at: targetURL)
    }
    
    @Test("Progress is reported correctly during sync")
    func testProgressIsReportedCorrectly() async throws {
        // Given
        let service = DeltaSyncService()
        let data = createTestBackupData(size: 10240)
        let localURL = try createTemporaryFile(with: data)
        
        var progressValues: [Double] = []
        
        // When
        _ = try await service.syncToCloud(
            localURL: localURL,
            remoteBaseURL: nil,
            uploadChunk: { _, _, _ in
                // Simulate upload delay
                try await Task.sleep(for: .milliseconds(10))
            },
            progress: { progress, _ in
                progressValues.append(progress)
            }
        )
        
        // Then
        #expect(!progressValues.isEmpty)
        #expect(progressValues.first! >= 0.0)
        #expect(progressValues.last! == 1.0)
        
        // Progress should be monotonic
        for i in 1..<progressValues.count {
            #expect(progressValues[i] >= progressValues[i-1])
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: localURL)
    }
    
    // MARK: - Helper Methods
    
    private func createTestBackupData(size: Int, seed: UInt64 = 0) -> Data {
        var generator = SeededRandomNumberGenerator(seed: seed)
        var data = Data(count: size)
        data.withUnsafeMutableBytes { ptr in
            for i in 0..<size {
                ptr[i] = UInt8.random(in: 0...255, using: &generator)
            }
        }
        return data
    }
    
    private func createTemporaryFile(with data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }
    
    private func createTestPayload(studentCount: Int) -> BackupPayload {
        var students: [[String: Any]] = []
        for i in 0..<studentCount {
            students.append([
                "studentID": "STUDENT\(String(format: "%03d", i))",
                "firstName": "Student",
                "lastName": "\(i)",
                "grade": "9th"
            ])
        }
        
        return BackupPayload(
            metadata: BackupMetadata(
                timestamp: Date(),
                deviceID: "TEST_DEVICE",
                totalEntityCount: studentCount,
                entityTypeCounts: ["Student": studentCount],
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

// Helper for deterministic random data
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
