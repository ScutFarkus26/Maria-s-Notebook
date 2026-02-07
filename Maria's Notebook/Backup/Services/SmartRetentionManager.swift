import Foundation

/// Manages smart backup retention with tiered strategy
/// Balances storage usage with historical data preservation
@MainActor
public final class SmartRetentionManager {
    
    // MARK: - Types
    
    public struct RetentionPolicy: Codable {
        public var dailyRetention: Int = 7      // Keep last 7 daily backups
        public var weeklyRetention: Int = 4     // Keep 4 weekly backups
        public var monthlyRetention: Int = 12   // Keep 12 monthly backups
        public var yearlyRetention: Int = 5     // Keep 5 yearly backups
        public var keepAllRecentDays: Int = 3   // Keep all backups from last 3 days
        
        public static let `default` = RetentionPolicy()
        
        public static let aggressive = RetentionPolicy(
            dailyRetention: 3,
            weeklyRetention: 2,
            monthlyRetention: 6,
            yearlyRetention: 2,
            keepAllRecentDays: 1
        )
        
        public static let conservative = RetentionPolicy(
            dailyRetention: 14,
            weeklyRetention: 8,
            monthlyRetention: 24,
            yearlyRetention: 10,
            keepAllRecentDays: 7
        )
    }
    
    public enum RetentionTier {
        case recent     // Keep all (within keepAllRecentDays)
        case daily      // Keep one per day
        case weekly     // Keep one per week
        case monthly    // Keep one per month
        case yearly     // Keep one per year
        case expired    // Should be deleted
    }
    
    public struct BackupClassification {
        public let url: URL
        public let fileName: String
        public let createdAt: Date
        public let fileSize: Int64
        public let tier: RetentionTier
        public let shouldKeep: Bool
        public let reason: String
    }
    
    public struct RetentionReport {
        public let totalBackups: Int
        public let backupsToKeep: Int
        public let backupsToDelete: Int
        public let spaceToReclaim: Int64
        public let classifications: [BackupClassification]
        
        public var formattedSpaceToReclaim: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            formatter.allowedUnits = [.useMB, .useGB]
            return formatter.string(fromByteCount: spaceToReclaim)
        }
    }
    
    // MARK: - Properties
    
    private var policy: RetentionPolicy
    
    // MARK: - Initialization
    
    public init(policy: RetentionPolicy = .default) {
        self.policy = policy
    }
    
    // MARK: - Analysis
    
    /// Analyzes backups and determines which should be kept/deleted
    /// - Parameter directory: Directory containing backups
    /// - Returns: Retention report with classifications
    public func analyzeBackups(in directory: URL) async throws -> RetentionReport {
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: directory.path) else {
            return RetentionReport(
                totalBackups: 0,
                backupsToKeep: 0,
                backupsToDelete: 0,
                spaceToReclaim: 0,
                classifications: []
            )
        }
        
        // Get all backup files with metadata
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return RetentionReport(
                totalBackups: 0,
                backupsToKeep: 0,
                backupsToDelete: 0,
                spaceToReclaim: 0,
                classifications: []
            )
        }
        
        let backupFiles = files.filter { $0.pathExtension == BackupFile.fileExtension }
        
        // Extract metadata for each backup
        var backups: [(url: URL, date: Date, size: Int64)] = []
        for file in backupFiles {
            let values = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let date = values?.creationDate ?? Date.distantPast
            let size = Int64(values?.fileSize ?? 0)
            backups.append((file, date, size))
        }
        
        // Sort by date (newest first)
        backups.sort { $0.date > $1.date }
        
        // Classify each backup
        let classifications = classifyBackups(backups)
        
        let toKeep = classifications.filter { $0.shouldKeep }
        let toDelete = classifications.filter { !$0.shouldKeep }
        let spaceToReclaim = toDelete.reduce(0) { $0 + $1.fileSize }
        
        return RetentionReport(
            totalBackups: backups.count,
            backupsToKeep: toKeep.count,
            backupsToDelete: toDelete.count,
            spaceToReclaim: spaceToReclaim,
            classifications: classifications
        )
    }
    
    /// Applies retention policy by deleting expired backups
    /// - Parameters:
    ///   - directory: Directory containing backups
    ///   - dryRun: If true, don't actually delete (for preview)
    /// - Returns: List of deleted backup URLs
    public func applyRetentionPolicy(
        in directory: URL,
        dryRun: Bool = false
    ) async throws -> [URL] {
        
        let report = try await analyzeBackups(in: directory)
        let toDelete = report.classifications.filter { !$0.shouldKeep }
        
        guard !dryRun else {
            return toDelete.map { $0.url }
        }
        
        var deleted: [URL] = []
        for classification in toDelete {
            do {
                try FileManager.default.removeItem(at: classification.url)
                deleted.append(classification.url)
            } catch {
                print("SmartRetentionManager: Failed to delete \(classification.fileName): \(error)")
            }
        }
        
        return deleted
    }
    
    // MARK: - Classification
    
    private func classifyBackups(_ backups: [(url: URL, date: Date, size: Int64)]) -> [BackupClassification] {
        let now = Date()
        let calendar = Calendar.current
        
        var recentBackups: [BackupClassification] = []
        var dailyBuckets: [String: BackupClassification] = [:]
        var weeklyBuckets: [String: BackupClassification] = [:]
        var monthlyBuckets: [String: BackupClassification] = [:]
        var yearlyBuckets: [String: BackupClassification] = [:]
        
        for (url, date, size) in backups {
            let age = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            
            // Recent backups - keep all
            if age <= policy.keepAllRecentDays {
                recentBackups.append(BackupClassification(
                    url: url,
                    fileName: url.lastPathComponent,
                    createdAt: date,
                    fileSize: size,
                    tier: .recent,
                    shouldKeep: true,
                    reason: "Recent backup (< \(policy.keepAllRecentDays) days old)"
                ))
                continue
            }
            
            // Daily backups
            let dayKey = calendar.startOfDay(for: date).ISO8601Format()
            if dailyBuckets[dayKey] == nil && dailyBuckets.count < policy.dailyRetention {
                let classification = BackupClassification(
                    url: url,
                    fileName: url.lastPathComponent,
                    createdAt: date,
                    fileSize: size,
                    tier: .daily,
                    shouldKeep: true,
                    reason: "Daily backup representative"
                )
                dailyBuckets[dayKey] = classification
                continue
            }
            
            // Weekly backups (one per week)
            let weekKey = weekIdentifier(for: date, calendar: calendar)
            if weeklyBuckets[weekKey] == nil && weeklyBuckets.count < policy.weeklyRetention {
                let classification = BackupClassification(
                    url: url,
                    fileName: url.lastPathComponent,
                    createdAt: date,
                    fileSize: size,
                    tier: .weekly,
                    shouldKeep: true,
                    reason: "Weekly backup representative"
                )
                weeklyBuckets[weekKey] = classification
                continue
            }
            
            // Monthly backups (one per month)
            let monthKey = monthIdentifier(for: date, calendar: calendar)
            if monthlyBuckets[monthKey] == nil && monthlyBuckets.count < policy.monthlyRetention {
                let classification = BackupClassification(
                    url: url,
                    fileName: url.lastPathComponent,
                    createdAt: date,
                    fileSize: size,
                    tier: .monthly,
                    shouldKeep: true,
                    reason: "Monthly backup representative"
                )
                monthlyBuckets[monthKey] = classification
                continue
            }
            
            // Yearly backups (one per year)
            let yearKey = yearIdentifier(for: date, calendar: calendar)
            if yearlyBuckets[yearKey] == nil && yearlyBuckets.count < policy.yearlyRetention {
                let classification = BackupClassification(
                    url: url,
                    fileName: url.lastPathComponent,
                    createdAt: date,
                    fileSize: size,
                    tier: .yearly,
                    shouldKeep: true,
                    reason: "Yearly backup representative"
                )
                yearlyBuckets[yearKey] = classification
                continue
            }
            
            // Expired - mark for deletion
            recentBackups.append(BackupClassification(
                url: url,
                fileName: url.lastPathComponent,
                createdAt: date,
                fileSize: size,
                tier: .expired,
                shouldKeep: false,
                reason: "Exceeds retention policy"
            ))
        }
        
        // Combine all classifications
        var all = recentBackups
        all.append(contentsOf: dailyBuckets.values)
        all.append(contentsOf: weeklyBuckets.values)
        all.append(contentsOf: monthlyBuckets.values)
        all.append(contentsOf: yearlyBuckets.values)
        
        // Sort by date (newest first)
        all.sort { $0.createdAt > $1.createdAt }
        
        return all
    }
    
    // MARK: - Time Identifiers
    
    private func weekIdentifier(for date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return "\(year)-W\(week)"
    }
    
    private func monthIdentifier(for date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "\(year)-\(String(format: "%02d", month))"
    }
    
    private func yearIdentifier(for date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        return "\(year)"
    }
    
    // MARK: - Policy Management
    
    public func updatePolicy(_ newPolicy: RetentionPolicy) {
        self.policy = newPolicy
    }
    
    public func currentPolicy() -> RetentionPolicy {
        return policy
    }
    
    /// Estimates storage savings from applying retention policy
    public func estimateSavings(in directory: URL) async throws -> StorageEstimate {
        let report = try await analyzeBackups(in: directory)
        
        let totalSize = report.classifications.reduce(0) { $0 + $1.fileSize }
        let keptSize = report.classifications.filter { $0.shouldKeep }.reduce(0) { $0 + $1.fileSize }
        let reclaimedSize = report.spaceToReclaim
        
        return StorageEstimate(
            totalSize: totalSize,
            sizeAfterCleanup: keptSize,
            spaceReclaimed: reclaimedSize,
            percentageSaved: totalSize > 0 ? Double(reclaimedSize) / Double(totalSize) * 100.0 : 0.0
        )
    }
}

// MARK: - Supporting Types

public struct StorageEstimate {
    public let totalSize: Int64
    public let sizeAfterCleanup: Int64
    public let spaceReclaimed: Int64
    public let percentageSaved: Double
    
    public var formattedTotal: String {
        formatBytes(totalSize)
    }
    
    public var formattedAfterCleanup: String {
        formatBytes(sizeAfterCleanup)
    }
    
    public var formattedReclaimed: String {
        formatBytes(spaceReclaimed)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - AutoBackupManager Integration

extension AutoBackupManager {
    
    /// Applies smart retention policy to auto-backups
    public func applySmartRetention(policy: SmartRetentionManager.RetentionPolicy) async {
        let retentionManager = SmartRetentionManager(policy: policy)
        
        let autoBackupDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto")
        
        do {
            let deleted = try await retentionManager.applyRetentionPolicy(in: autoBackupDir, dryRun: false)
            print("SmartRetention: Deleted \(deleted.count) expired backups")
        } catch {
            print("SmartRetention: Failed to apply policy: \(error)")
        }
    }
}
