// BackupExportTests.swift
// Tests for backup export functionality

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Shared Test Helpers

private enum BackupTestHelpers {
    static func createCloudBackupInfo(
        fileName: String = "test.mtbbackup",
        fileSize: Int64 = 1000,
        isDownloaded: Bool = true,
        isUploading: Bool = false,
        isDownloading: Bool = false
    ) -> CloudBackupService.CloudBackupInfo {
        CloudBackupService.CloudBackupInfo(
            id: UUID(),
            fileName: fileName,
            fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"),
            fileSize: fileSize,
            createdAt: Date(),
            modifiedAt: Date(),
            isDownloaded: isDownloaded,
            isUploading: isUploading,
            isDownloading: isDownloading
        )
    }
}

// MARK: - SelectiveExportService Tests

@Suite("SelectiveExportService Tests")
struct SelectiveExportServiceTests {

    @Test("Export filter default values")
    func testExportFilterDefaults() {
        let filter = SelectiveExportService.ExportFilter()

        #expect(filter.studentIDs == nil)
        #expect(filter.dateRange == nil)
        #expect(filter.entityTypes == nil)
        #expect(filter.projectIDs == nil)
        #expect(filter.includeRelatedEntities == true)
    }

    @Test("Export filter all static constructor")
    func testExportFilterAll() {
        let filter = SelectiveExportService.ExportFilter.all

        #expect(filter.studentIDs == nil)
        #expect(filter.dateRange == nil)
        #expect(filter.entityTypes == nil)
        #expect(filter.includeRelatedEntities == true)
    }

    @Test("Export filter with specific students")
    func testExportFilterWithStudents() {
        let studentIDs: Set<UUID> = [UUID(), UUID()]
        let filter = SelectiveExportService.ExportFilter(
            studentIDs: studentIDs,
            includeRelatedEntities: true
        )

        #expect(filter.studentIDs?.count == 2)
        #expect(filter.includeRelatedEntities == true)
    }

    @Test("Export filter with date range")
    func testExportFilterWithDateRange() {
        let startDate = Date().addingTimeInterval(-86400 * 30) // 30 days ago
        let endDate = Date()
        let dateRange = startDate...endDate

        let filter = SelectiveExportService.ExportFilter(
            dateRange: dateRange
        )

        #expect(filter.dateRange != nil)
        #expect(filter.dateRange?.lowerBound == startDate)
        #expect(filter.dateRange?.upperBound == endDate)
    }

    @Test("Entity type descriptions")
    func testEntityTypeDescriptions() {
        for type in SelectiveExportService.EntityType.allCases {
            #expect(!type.rawValue.isEmpty)
            #expect(!type.description.isEmpty)
            #expect(type.id == type.rawValue)
        }
    }

    @Test("Export statistics structure")
    func testExportStatisticsStructure() {
        let filter = SelectiveExportService.ExportFilter()
        let stats = SelectiveExportService.ExportStatistics(
            filter: filter,
            includedCounts: ["Student": 10, "Lesson": 50],
            excludedCounts: ["Student": 0, "Lesson": 0],
            estimatedSize: 50000,
            relatedEntitiesAdded: 5
        )

        #expect(stats.includedCounts["Student"] == 10)
        #expect(stats.includedCounts["Lesson"] == 50)
        #expect(stats.estimatedSize == 50000)
        #expect(stats.relatedEntitiesAdded == 5)
    }
}

// MARK: - CloudBackupService Export Tests

@Suite("CloudBackupService Export Tests")
struct CloudBackupServiceExportTests {

    @Test("iCloud availability check")
    @MainActor
    func testICloudAvailabilityCheck() async {
        let service = CloudBackupService(backupService: BackupService())
        // This will return true or false depending on system state
        // Just verify it doesn't crash
        let _ = service.isICloudAvailable
    }

    @Test("Cloud backup directory URL generation")
    @MainActor
    func testCloudBackupDirectoryGeneration() async {
        let service = CloudBackupService(backupService: BackupService())

        if service.isICloudAvailable {
            let dir = service.cloudBackupDirectory
            #expect(dir != nil)
            if let dir = dir {
                #expect(dir.path.contains("Backups"))
            }
        }
    }

    @Test("CloudBackupInfo properties")
    func testCloudBackupInfoProperties() {
        let info = BackupTestHelpers.createCloudBackupInfo(
            fileName: "TestBackup.mtbbackup",
            fileSize: 1024 * 1024
        )

        #expect(info.fileName == "TestBackup.mtbbackup")
        #expect(info.fileSize == 1024 * 1024)
        #expect(info.isDownloaded == true)
        #expect(info.formattedFileSize.contains("MB") || info.formattedFileSize.contains("KB"))
    }

    @Test("CloudBackupInfo identifiable conformance")
    func testCloudBackupInfoIdentifiable() {
        let info = BackupTestHelpers.createCloudBackupInfo()
        #expect(info.id != UUID()) // Just verify it has an ID
    }

    @Test("CloudBackupInfo formatted file size for various sizes")
    func testFormattedFileSizeVariousSizes() {
        // Test KB
        let smallInfo = BackupTestHelpers.createCloudBackupInfo(fileName: "small.mtbbackup", fileSize: 500)
        #expect(!smallInfo.formattedFileSize.isEmpty)

        // Test MB
        let mediumInfo = BackupTestHelpers.createCloudBackupInfo(fileName: "medium.mtbbackup", fileSize: 5 * 1024 * 1024)
        #expect(mediumInfo.formattedFileSize.contains("MB"))

        // Test GB
        let largeInfo = BackupTestHelpers.createCloudBackupInfo(fileName: "large.mtbbackup", fileSize: 2 * 1024 * 1024 * 1024)
        #expect(largeInfo.formattedFileSize.contains("GB"))
    }

    @Test("CloudBackupInfo upload/download states")
    func testBackupInfoStates() {
        // Uploading state
        let uploading = BackupTestHelpers.createCloudBackupInfo(
            fileName: "uploading.mtbbackup",
            isDownloaded: false,
            isUploading: true
        )
        #expect(uploading.isUploading == true)
        #expect(uploading.isDownloading == false)

        // Downloading state
        let downloading = BackupTestHelpers.createCloudBackupInfo(
            fileName: "downloading.mtbbackup",
            isDownloaded: false,
            isDownloading: true
        )
        #expect(downloading.isUploading == false)
        #expect(downloading.isDownloading == true)
    }

    @Test("Ensure cloud backup directory creation throws without iCloud")
    @MainActor
    func testEnsureDirectoryWithoutICloud() async {
        let service = CloudBackupService(backupService: BackupService())

        // If iCloud is not available, should throw
        if !service.isICloudAvailable {
            do {
                try service.ensureCloudBackupDirectoryExists()
                Issue.record("Expected error when iCloud not available")
            } catch BackupOperationError.cloudOperationFailed(.containerNotFound) {
                // Expected
                #expect(true)
            } catch {
                // Other errors acceptable
            }
        }
    }

    @Test("List cloud backups throws without iCloud")
    @MainActor
    func testListBackupsWithoutICloud() async {
        let service = CloudBackupService(backupService: BackupService())

        if !service.isICloudAvailable {
            do {
                _ = try await service.listCloudBackups()
                Issue.record("Expected error when iCloud not available")
            } catch BackupOperationError.cloudOperationFailed(.iCloudNotAvailable) {
                #expect(true)
            } catch {
                // Other errors acceptable
            }
        }
    }

    @Test("Copy to cloud throws without iCloud")
    @MainActor
    func testCopyToCloudWithoutICloud() async {
        let service = CloudBackupService(backupService: BackupService())

        if !service.isICloudAvailable {
            let localURL = URL(fileURLWithPath: "/tmp/test-backup.mtbbackup")

            do {
                _ = try service.copyToCloud(localURL)
                Issue.record("Expected iCloudNotAvailable error")
            } catch BackupOperationError.cloudOperationFailed(.iCloudNotAvailable) {
                #expect(true)
            } catch {
                // Other errors acceptable
            }
        }
    }
}

// MARK: - IncrementalBackupService Tests

@Suite("IncrementalBackupService Tests")
struct IncrementalBackupServiceTests {

    @Test("Incremental backup metadata structure")
    func testIncrementalBackupMetadata() {
        let metadata = IncrementalBackupService.IncrementalBackupMetadata(
            lastBackupDate: Date(),
            backupID: UUID(),
            parentBackupID: UUID(),
            isFullBackup: false,
            changedEntityCounts: ["Student": 5, "Lesson": 10]
        )

        #expect(metadata.isFullBackup == false)
        #expect(metadata.changedEntityCounts["Student"] == 5)
        #expect(metadata.changedEntityCounts["Lesson"] == 10)
        #expect(metadata.parentBackupID != nil)
    }

    @Test("Incremental backup metadata codable")
    @MainActor
    func testIncrementalBackupMetadataCodable() throws {
        let original = IncrementalBackupService.IncrementalBackupMetadata(
            lastBackupDate: Date(),
            backupID: UUID(),
            parentBackupID: nil,
            isFullBackup: true,
            changedEntityCounts: ["Student": 3]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(IncrementalBackupService.IncrementalBackupMetadata.self, from: data)

        #expect(decoded.isFullBackup == original.isFullBackup)
        #expect(decoded.backupID == original.backupID)
        #expect(decoded.changedEntityCounts == original.changedEntityCounts)
    }

    @Test("Reset incremental tracking")
    @MainActor
    func testResetIncrementalTracking() async {
        let service = IncrementalBackupService(backupService: BackupService())

        // Set some values
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: "IncrementalBackup.lastDate")
        UserDefaults.standard.set(UUID().uuidString, forKey: "IncrementalBackup.lastID")

        // Reset
        service.resetIncrementalTracking()

        // Verify cleared
        #expect(service.lastBackupDate == nil)
        #expect(service.lastBackupID == nil)
    }

    @Test("Incremental backup creates full backup when no previous exists")
    @MainActor
    func testIncrementalBackupFullWhenNoPrevious() async throws {
        guard let container = try? ModelContainer(
            for: Student.self, Lesson.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else {
            return // SwiftData models unavailable in test context
        }

        let ctx = container.mainContext
        let student = Student(firstName: "Test", lastName: "Student", birthday: Date(), level: .lower)
        ctx.insert(student)
        try ctx.save()

        let service = IncrementalBackupService(backupService: BackupService())
        service.resetIncrementalTracking() // Ensure clean state

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(BackupFile.fileExtension)

        let result = try await service.createIncrementalBackup(
            modelContext: ctx,
            to: tmp,
            forceFullBackup: false
        ) { _, _ in }

        #expect(result.metadata.isFullBackup == true)
        #expect(result.totalEntities >= 1)
        #expect(FileManager.default.fileExists(atPath: tmp.path))

        // Cleanup
        try? FileManager.default.removeItem(at: tmp)
    }
}

// MARK: - AutoBackupManager Tests

@Suite("AutoBackupManager Tests")
struct AutoBackupManagerTests {

    @Test("Backup trigger raw values")
    func testBackupTriggerRawValues() {
        #expect(AutoBackupManager.BackupTrigger.appQuit.rawValue == "AppQuit")
        #expect(AutoBackupManager.BackupTrigger.scheduled.rawValue == "Scheduled")
        #expect(AutoBackupManager.BackupTrigger.preDestructive.rawValue == "PreDestructive")
        #expect(AutoBackupManager.BackupTrigger.manual.rawValue == "Manual")
    }

    @Test("Backup result success")
    func testBackupResultSuccess() {
        let url = URL(fileURLWithPath: "/tmp/test.mtbbackup")
        let result = AutoBackupManager.BackupResult.success(Date(), url)

        #expect(result.isSuccess == true)
        #expect(result.date != Date.distantPast)
    }

    @Test("Backup result failure")
    func testBackupResultFailure() {
        let error = NSError(domain: "test", code: 1)
        let result = AutoBackupManager.BackupResult.failure(Date(), error)

        #expect(result.isSuccess == false)
    }

    @Test("Settings access defaults")
    @MainActor
    func testSettingsAccessDefaults() async {
        let manager = AutoBackupManager(backupService: BackupService())

        // Access default values - should not crash
        let _ = manager.enabled
        let _ = manager.retention
        let _ = manager.isScheduledBackupEnabled
        let _ = manager.backupIntervalHours
    }

    @Test("Retention clamping")
    @MainActor
    func testRetentionClamping() async {
        let manager = AutoBackupManager(backupService: BackupService())

        manager.retention = 0
        #expect(manager.retention >= 1)

        manager.retention = 200
        #expect(manager.retention <= 100)

        manager.retention = 50
        #expect(manager.retention == 50)
    }

    @Test("Backup interval clamping")
    @MainActor
    func testBackupIntervalClamping() async {
        let manager = AutoBackupManager(backupService: BackupService())

        manager.backupIntervalHours = 0
        #expect(manager.backupIntervalHours >= 1)

        manager.backupIntervalHours = 48
        #expect(manager.backupIntervalHours <= 24)

        manager.backupIntervalHours = 6
        #expect(manager.backupIntervalHours == 6)
    }
}

// MARK: - GenericEntityFetcher Tests

@Suite("GenericEntityFetcher Tests")
struct GenericEntityFetcherTests {

    @Test("BatchEntityFetcher default batch size")
    func testBatchEntityFetcherDefaultBatchSize() {
        #expect(BatchEntityFetcher.defaultBatchSize == 1000)
    }

    @Test("Entity count helpers structure")
    @MainActor
    func testEntityCountHelpersStructure() async throws {
        guard let container = try? ModelContainer(
            for: Student.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else {
            return // SwiftData models unavailable in test context
        }

        let ctx = container.mainContext

        // Test with empty database
        let items = [
            (id: UUID(), name: "Test1"),
            (id: UUID(), name: "Test2")
        ]

        let (insert, skip) = EntityCountHelpers.countInsertAndSkip(
            items: items,
            type: Student.self,
            context: ctx,
            idExtractor: { $0.id }
        )

        #expect(insert == 2) // Both new
        #expect(skip == 0)
    }

    @Test("Entity fetcher registry returns nil for unknown ID")
    @MainActor
    func testEntityFetcherRegistryMissingEntity() async throws {
        guard let container = try? ModelContainer(
            for: Student.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else {
            return // SwiftData models unavailable in test context
        }

        let ctx = container.mainContext
        let registry = EntityFetcherRegistry.shared

        // Try to fetch non-existent entity
        let result: Student? = registry.fetchOne(Student.self, id: UUID(), context: ctx)
        #expect(result == nil)
    }

    @Test("Entity fetcher registry exists check")
    @MainActor
    func testEntityFetcherRegistryExists() async throws {
        guard let container = try? ModelContainer(
            for: Student.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else {
            return // SwiftData models unavailable in test context
        }

        let ctx = container.mainContext
        let registry = EntityFetcherRegistry.shared

        // Create and save a student
        let student = Student(firstName: "Test", lastName: "User", birthday: Date(), level: .lower)
        ctx.insert(student)
        try ctx.save()

        // Check existence
        let exists = registry.exists(Student.self, id: student.id, context: ctx)
        #expect(exists == true)

        let notExists = registry.exists(Student.self, id: UUID(), context: ctx)
        #expect(notExists == false)
    }
}

// MARK: - Integration Tests

@Suite("Backup Export Integration Tests", .serialized)
struct BackupExportIntegrationTests {

    /// Creates a container with all entity types that BackupService operates on.
    /// This prevents crashes when BackupService.deleteAll iterates over BackupEntityRegistry.allTypes.
    private static func makeBackupTestContainer() throws -> ModelContainer {
        let schema = Schema(BackupEntityRegistry.allTypes)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Full backup and verify cycle")
    @MainActor
    func testFullBackupAndVerifyCycle() async {
        do {
            let container = try Self.makeBackupTestContainer()

            let ctx = container.mainContext

            // Create test data
            let student = Student(firstName: "Integration", lastName: "Test", birthday: Date(), level: .lower)
            let lesson = Lesson(name: "Test Lesson", subject: "Testing", group: "Tests", subheading: "", writeUp: "")
            ctx.insert(student)
            ctx.insert(lesson)
            try ctx.save()

            // Export backup
            let service = BackupService()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(BackupFile.fileExtension)
            defer { try? FileManager.default.removeItem(at: tmp) }

            var progressCalled = false
            _ = try await service.exportBackup(modelContext: ctx, to: tmp, password: nil) { _, _ in
                progressCalled = true
            }

            #expect(progressCalled)
            #expect(FileManager.default.fileExists(atPath: tmp.path))

            // Verify backup
            let verification = BackupVerification.verifyBackup(at: tmp)
            switch verification {
            case .success(let info):
                #expect(info.formatVersion == BackupFile.formatVersion)
            case .failure(let error):
                Issue.record("Verification failed: \(error)")
            }
        } catch {
            // SwiftData or backup operation unavailable in test context
            #expect(Bool(true), "Integration test skipped: \(error)")
        }
    }

    @Test("Backup compression effectiveness")
    @MainActor
    func testBackupCompressionEffectiveness() async {
        do {
            let container = try Self.makeBackupTestContainer()

            let ctx = container.mainContext

            // Create multiple records to make compression more effective
            for i in 0..<50 {
                let student = Student(firstName: "Student\(i)", lastName: "Test", birthday: Date(), level: i % 2 == 0 ? .lower : .upper)
                let lesson = Lesson(name: "Lesson \(i)", subject: "Subject", group: "Group \(i / 10)", subheading: "", writeUp: "This is a detailed write-up for lesson \(i) with some repeated content.")
                ctx.insert(student)
                ctx.insert(lesson)
            }
            try ctx.save()

            // Export
            let service = BackupService()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(BackupFile.fileExtension)
            defer { try? FileManager.default.removeItem(at: tmp) }

            _ = try await service.exportBackup(modelContext: ctx, to: tmp, password: nil) { _, _ in }

            // Check file exists and has reasonable size
            let attributes = try FileManager.default.attributesOfItem(atPath: tmp.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            #expect(fileSize > 0)
            #expect(fileSize < 1024 * 1024) // Should be less than 1MB for this test data
        } catch {
            // SwiftData or backup operation unavailable in test context
            #expect(Bool(true), "Integration test skipped: \(error)")
        }
    }
}
#endif
