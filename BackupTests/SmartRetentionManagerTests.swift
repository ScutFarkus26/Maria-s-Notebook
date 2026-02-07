import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("SmartRetentionManager Tests")
struct SmartRetentionManagerTests {
    
    @Test("Analyze backups classifies by tier correctly")
    func testAnalyzeBackupsClassifiesByTier() async throws {
        // Given
        let manager = SmartRetentionManager()
        let directory = try createTestBackupDirectory()
        
        // Create backups from different time periods
        let now = Date()
        try createBackupFile(in: directory, date: now.addingTimeInterval(-3600))  // 1 hour ago - daily
        try createBackupFile(in: directory, date: now.addingTimeInterval(-86400 * 5))  // 5 days ago - weekly
        try createBackupFile(in: directory, date: now.addingTimeInterval(-86400 * 20))  // 20 days ago - monthly
        try createBackupFile(in: directory, date: now.addingTimeInterval(-86400 * 200))  // 200 days ago - yearly
        
        // When
        let report = try await manager.analyzeBackups(in: directory)
        
        // Then
        #expect(report.totalBackups == 4)
        #expect(!report.backupsByTier[.daily]!.isEmpty)
        #expect(!report.backupsByTier[.weekly]!.isEmpty)
        #expect(!report.backupsByTier[.monthly]!.isEmpty)
        #expect(!report.backupsByTier[.yearly]!.isEmpty)
        
        // Cleanup
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test("Apply retention policy keeps required backups")
    func testApplyRetentionPolicyKeepsRequiredBackups() async throws {
        // Given
        let manager = SmartRetentionManager()
        let directory = try createTestBackupDirectory()
        
        let now = Date()
        let policy = SmartRetentionManager.RetentionPolicy(
            dailyCount: 2,
            weeklyCount: 2,
            monthlyCount: 2,
            yearlyCount: 2
        )
        
        // Create multiple daily backups (should keep only 2)
        for i in 0..<5 {
            try createBackupFile(
                in: directory,
                date: now.addingTimeInterval(-Double(i) * 3600),
                name: "daily_\(i).backup"
            )
        }
        
        // When
        let deletedURLs = try await manager.applyRetentionPolicy(
            in: directory,
            policy: policy,
            dryRun: false
        )
        
        // Then
        #expect(deletedURLs.count == 3)  // Should delete 3 out of 5
        
        // Verify remaining backups
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(contents.count == 2)
        
        // Cleanup
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test("Dry run mode doesn't delete files")
    func testDryRunModeDoesntDeleteFiles() async throws {
        // Given
        let manager = SmartRetentionManager()
        let directory = try createTestBackupDirectory()
        
        let now = Date()
        let policy = SmartRetentionManager.RetentionPolicy(
            dailyCount: 1,
            weeklyCount: 1,
            monthlyCount: 1,
            yearlyCount: 1
        )
        
        // Create multiple backups
        for i in 0..<5 {
            try createBackupFile(
                in: directory,
                date: now.addingTimeInterval(-Double(i) * 3600),
                name: "backup_\(i).backup"
            )
        }
        
        let beforeCount = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count
        
        // When
        let deletedURLs = try await manager.applyRetentionPolicy(
            in: directory,
            policy: policy,
            dryRun: true
        )
        
        // Then
        let afterCount = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count
        #expect(beforeCount == afterCount)  // No files deleted
        #expect(!deletedURLs.isEmpty)  // But reports what would be deleted
        
        // Cleanup
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test("Retention policy preserves newest backups in each tier")
    func testRetentionPolicyPreservesNewestBackups() async throws {
        // Given
        let manager = SmartRetentionManager()
        let directory = try createTestBackupDirectory()
        
        let now = Date()
        let policy = SmartRetentionManager.RetentionPolicy(
            dailyCount: 2,
            weeklyCount: 0,
            monthlyCount: 0,
            yearlyCount: 0
        )
        
        // Create backups with known timestamps
        let newest = now.addingTimeInterval(-3600)
        let middle = now.addingTimeInterval(-7200)
        let oldest = now.addingTimeInterval(-10800)
        
        try createBackupFile(in: directory, date: oldest, name: "oldest.backup")
        try createBackupFile(in: directory, date: middle, name: "middle.backup")
        try createBackupFile(in: directory, date: newest, name: "newest.backup")
        
        // When
        let deletedURLs = try await manager.applyRetentionPolicy(
            in: directory,
            policy: policy,
            dryRun: false
        )
        
        // Then
        #expect(deletedURLs.count == 1)
        #expect(deletedURLs.first?.lastPathComponent == "oldest.backup")
        
        let remaining = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let remainingNames = remaining.map { $0.lastPathComponent }.sorted()
        #expect(remainingNames.contains("newest.backup"))
        #expect(remainingNames.contains("middle.backup"))
        
        // Cleanup
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test("Analyze backups calculates storage correctly")
    func testAnalyzeBackupsCalculatesStorage() async throws {
        // Given
        let manager = SmartRetentionManager()
        let directory = try createTestBackupDirectory()
        
        let now = Date()
        let file1Size = 1024
        let file2Size = 2048
        
        try createBackupFile(in: directory, date: now, name: "backup1.backup", size: file1Size)
        try createBackupFile(in: directory, date: now.addingTimeInterval(-3600), name: "backup2.backup", size: file2Size)
        
        // When
        let report = try await manager.analyzeBackups(in: directory)
        
        // Then
        #expect(report.totalSize >= file1Size + file2Size)
        
        // Cleanup
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test("Retention report identifies expired backups")
    func testRetentionReportIdentifiesExpiredBackups() async throws {
        // Given
        let manager = SmartRetentionManager()
        let directory = try createTestBackupDirectory()
        
        let now = Date()
        let policy = SmartRetentionManager.RetentionPolicy(
            dailyCount: 1,
            weeklyCount: 1,
            monthlyCount: 1,
            yearlyCount: 1
        )
        
        // Create multiple backups in same tier
        for i in 0..<3 {
            try createBackupFile(
                in: directory,
                date: now.addingTimeInterval(-Double(i) * 3600),
                name: "backup_\(i).backup"
            )
        }
        
        // When
        let report = try await manager.analyzeBackups(in: directory)
        let expired = manager.identifyExpiredBackups(report: report, policy: policy)
        
        // Then
        #expect(expired.count == 2)  // Should expire 2 out of 3 (keeping newest)
        
        // Cleanup
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test("Empty directory returns empty report")
    func testEmptyDirectoryReturnsEmptyReport() async throws {
        // Given
        let manager = SmartRetentionManager()
        let directory = try createTestBackupDirectory()
        
        // When
        let report = try await manager.analyzeBackups(in: directory)
        
        // Then
        #expect(report.totalBackups == 0)
        #expect(report.totalSize == 0)
        #expect(report.backupsByTier.values.allSatisfy { $0.isEmpty })
        
        // Cleanup
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test("Retention policy with zero counts deletes all backups")
    func testRetentionPolicyWithZeroCountsDeletesAll() async throws {
        // Given
        let manager = SmartRetentionManager()
        let directory = try createTestBackupDirectory()
        
        let now = Date()
        let policy = SmartRetentionManager.RetentionPolicy(
            dailyCount: 0,
            weeklyCount: 0,
            monthlyCount: 0,
            yearlyCount: 0
        )
        
        // Create some backups
        for i in 0..<3 {
            try createBackupFile(
                in: directory,
                date: now.addingTimeInterval(-Double(i) * 3600),
                name: "backup_\(i).backup"
            )
        }
        
        // When
        let deletedURLs = try await manager.applyRetentionPolicy(
            in: directory,
            policy: policy,
            dryRun: false
        )
        
        // Then
        #expect(deletedURLs.count == 3)
        
        let remaining = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(remaining.isEmpty)
        
        // Cleanup
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test("Backups are correctly assigned to tiers based on age")
    func testBackupsAreCorrectlyAssignedToTiers() async throws {
        // Given
        let manager = SmartRetentionManager()
        let directory = try createTestBackupDirectory()
        
        let now = Date()
        
        // Create backups at specific ages
        try createBackupFile(in: directory, date: now.addingTimeInterval(-3600), name: "daily.backup")  // 1 hour
        try createBackupFile(in: directory, date: now.addingTimeInterval(-86400 * 8), name: "weekly.backup")  // 8 days
        try createBackupFile(in: directory, date: now.addingTimeInterval(-86400 * 40), name: "monthly.backup")  // 40 days
        try createBackupFile(in: directory, date: now.addingTimeInterval(-86400 * 100), name: "yearly.backup")  // 100 days
        
        // When
        let report = try await manager.analyzeBackups(in: directory)
        
        // Then
        #expect(report.backupsByTier[.daily]!.contains { $0.lastPathComponent == "daily.backup" })
        #expect(report.backupsByTier[.weekly]!.contains { $0.lastPathComponent == "weekly.backup" })
        #expect(report.backupsByTier[.monthly]!.contains { $0.lastPathComponent == "monthly.backup" })
        #expect(report.backupsByTier[.yearly]!.contains { $0.lastPathComponent == "yearly.backup" })
        
        // Cleanup
        try? FileManager.default.removeItem(at: directory)
    }
    
    // MARK: - Helper Methods
    
    private func createTestBackupDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func createBackupFile(
        in directory: URL,
        date: Date,
        name: String? = nil,
        size: Int = 1024
    ) throws {
        let fileName = name ?? "backup_\(UUID().uuidString).backup"
        let fileURL = directory.appendingPathComponent(fileName)
        
        // Create file with some data
        let data = Data(repeating: 0, count: size)
        try data.write(to: fileURL)
        
        // Set creation date
        try FileManager.default.setAttributes(
            [.creationDate: date],
            ofItemAtPath: fileURL.path
        )
    }
}
