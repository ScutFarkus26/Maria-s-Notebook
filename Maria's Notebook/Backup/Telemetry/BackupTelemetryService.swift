import Foundation
import SwiftUI
import OSLog

/// Collects and reports telemetry data for backup/restore operations
/// Helps track success rates, performance, and identify issues
@MainActor
public final class BackupTelemetryService {
    
    // MARK: - Types
    
    public struct TelemetryEvent: Codable, Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let eventType: EventType
        public let operation: OperationType
        public let success: Bool
        public let duration: TimeInterval?
        public let entityCount: Int?
        public let fileSize: Int64?
        public let uncompressedSize: Int64?
        public let errorMessage: String?
        public let metadata: [String: String]
        
        public init(
            id: UUID = UUID(),
            timestamp: Date,
            eventType: EventType,
            operation: OperationType,
            success: Bool,
            duration: TimeInterval? = nil,
            entityCount: Int? = nil,
            fileSize: Int64? = nil,
            uncompressedSize: Int64? = nil,
            errorMessage: String? = nil,
            metadata: [String: String] = [:]
        ) {
            self.id = id
            self.timestamp = timestamp
            self.eventType = eventType
            self.operation = operation
            self.success = success
            self.duration = duration
            self.entityCount = entityCount
            self.fileSize = fileSize
            self.uncompressedSize = uncompressedSize
            self.errorMessage = errorMessage
            self.metadata = metadata
        }
        
        public enum EventType: String, Codable {
            case backupStarted
            case backupCompleted
            case backupFailed
            case restoreStarted
            case restoreCompleted
            case restoreFailed
            case validationPerformed
            case integrityCheckPerformed
            case cloudSyncStarted
            case cloudSyncCompleted
            case migrationPerformed
        }
        
        public enum OperationType: String, Codable {
            case standardBackup
            case streamingBackup
            case incrementalBackup
            case standardRestore
            case transactionalRestore
            case cloudSync
            case integrityCheck
            case migration
        }
    }
    
    public struct PerformanceMetrics: Codable, Sendable {
        public var averageBackupDuration: TimeInterval
        public var averageRestoreDuration: TimeInterval
        public var averageFileSize: Int64
        public var averageCompressionRatio: Double
        public var backupSuccessRate: Double
        public var restoreSuccessRate: Double
        
        public var formattedAvgBackupTime: String {
            formatDuration(averageBackupDuration)
        }
        
        public var formattedAvgRestoreTime: String {
            formatDuration(averageRestoreDuration)
        }
        
        public var formattedAvgFileSize: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: averageFileSize)
        }
        
        private func formatDuration(_ duration: TimeInterval) -> String {
            if duration < 60 {
                return String(format: "%.1fs", duration)
            } else {
                let minutes = Int(duration / 60)
                let seconds = Int(duration) % 60
                return "\(minutes)m \(seconds)s"
            }
        }
    }
    
    public struct ErrorCount: Sendable {
        public let error: String
        public let count: Int
    }
    
    public struct TelemetryReport: Identifiable, Sendable {
        public let id: UUID
        public let generatedAt: Date
        public let periodStart: Date
        public let periodEnd: Date
        public let totalEvents: Int
        public let totalBackups: Int
        public let totalRestores: Int
        public let successfulBackups: Int
        public let failedBackups: Int
        public let successfulRestores: Int
        public let failedRestores: Int
        public let metrics: PerformanceMetrics
        public let topErrors: [ErrorCount]
        public let deviceInfo: DeviceInfo
        
        public init(
            id: UUID = UUID(),
            generatedAt: Date,
            periodStart: Date,
            periodEnd: Date,
            totalEvents: Int,
            totalBackups: Int,
            totalRestores: Int,
            successfulBackups: Int,
            failedBackups: Int,
            successfulRestores: Int,
            failedRestores: Int,
            metrics: PerformanceMetrics,
            topErrors: [ErrorCount],
            deviceInfo: DeviceInfo
        ) {
            self.id = id
            self.generatedAt = generatedAt
            self.periodStart = periodStart
            self.periodEnd = periodEnd
            self.totalEvents = totalEvents
            self.totalBackups = totalBackups
            self.totalRestores = totalRestores
            self.successfulBackups = successfulBackups
            self.failedBackups = failedBackups
            self.successfulRestores = successfulRestores
            self.failedRestores = failedRestores
            self.metrics = metrics
            self.topErrors = topErrors
            self.deviceInfo = deviceInfo
        }
    }
    
    public struct DeviceInfo: Codable, Sendable {
        public let model: String
        public let osVersion: String
        public let appVersion: String
        public let appBuild: String
    }
    
    // MARK: - State
    
    public private(set) var recentEvents: [TelemetryEvent] = []
    public private(set) var currentMetrics: PerformanceMetrics?
    
    // MARK: - Properties
    
    private let maxStoredEvents = BatchingConstants.defaultBatchSize
    private let persistenceKey = "BackupTelemetry.events"
    
    // MARK: - Initialization
    
    public init() {
        loadPersistedEvents()
        updateMetrics()
    }
    
    // MARK: - Event Recording
    
    /// Records a telemetry event
    public func record(_ event: TelemetryEvent) {
        recentEvents.insert(event, at: 0)
        
        // Limit stored events
        if recentEvents.count > maxStoredEvents {
            recentEvents = Array(recentEvents.prefix(maxStoredEvents))
        }
        
        // Persist asynchronously
        Task {
            await persistEvents()
        }
        
        // Update metrics
        updateMetrics()
    }
    
    /// Records a backup operation
    public func recordBackup(
        operation: TelemetryEvent.OperationType,
        success: Bool,
        duration: TimeInterval,
        entityCount: Int,
        fileSize: Int64,
        uncompressedSize: Int64? = nil,
        error: Error? = nil,
        metadata: [String: String] = [:]
    ) {
        let eventType: TelemetryEvent.EventType = success ? .backupCompleted : .backupFailed
        
        record(TelemetryEvent(
            timestamp: Date(),
            eventType: eventType,
            operation: operation,
            success: success,
            duration: duration,
            entityCount: entityCount,
            fileSize: fileSize,
            uncompressedSize: uncompressedSize,
            errorMessage: error?.localizedDescription,
            metadata: metadata
        ))
    }
    
    /// Records a restore operation
    public func recordRestore(
        operation: TelemetryEvent.OperationType,
        success: Bool,
        duration: TimeInterval,
        entityCount: Int,
        error: Error? = nil,
        metadata: [String: String] = [:]
    ) {
        let eventType: TelemetryEvent.EventType = success ? .restoreCompleted : .restoreFailed
        
        record(TelemetryEvent(
            timestamp: Date(),
            eventType: eventType,
            operation: operation,
            success: success,
            duration: duration,
            entityCount: entityCount,
            fileSize: nil,
            errorMessage: error?.localizedDescription,
            metadata: metadata
        ))
    }
    
    /// Records an integrity check
    public func recordIntegrityCheck(
        filesChecked: Int,
        corruptedFiles: Int,
        duration: TimeInterval
    ) {
        record(TelemetryEvent(
            timestamp: Date(),
            eventType: .integrityCheckPerformed,
            operation: .integrityCheck,
            success: corruptedFiles == 0,
            duration: duration,
            entityCount: filesChecked,
            fileSize: nil,
            errorMessage: corruptedFiles > 0 ? "Found \(corruptedFiles) corrupted files" : nil,
            metadata: ["corruptedFiles": "\(corruptedFiles)"]
        ))
    }
    
    // MARK: - Metrics Calculation
    
    private func updateMetrics() {
        let backups = recentEvents.filter { event in
            event.eventType == .backupCompleted || event.eventType == .backupFailed
        }
        
        let restores = recentEvents.filter { event in
            event.eventType == .restoreCompleted || event.eventType == .restoreFailed
        }
        
        let successfulBackups = backups.filter { $0.success }
        let successfulRestores = restores.filter { $0.success }
        
        let avgBackupDuration = successfulBackups.compactMap { $0.duration }.average()
        let avgRestoreDuration = successfulRestores.compactMap { $0.duration }.average()
        let avgFileSize = successfulBackups.compactMap { $0.fileSize }.average()
        
        // Calculate compression ratio from backups with both fileSize and uncompressedSize
        let compressionRatios = successfulBackups.compactMap { event -> Double? in
            guard let compressed = event.fileSize, let uncompressed = event.uncompressedSize, uncompressed > 0 else {
                return nil
            }
            return Double(compressed) / Double(uncompressed)
        }
        let avgCompressionRatio = compressionRatios.isEmpty ? 0.0 : compressionRatios.reduce(0, +) / Double(compressionRatios.count)
        
        let backupSuccessRate = backups.isEmpty ? 0.0 : Double(successfulBackups.count) / Double(backups.count)
        let restoreSuccessRate = restores.isEmpty ? 0.0 : Double(successfulRestores.count) / Double(restores.count)
        
        currentMetrics = PerformanceMetrics(
            averageBackupDuration: avgBackupDuration,
            averageRestoreDuration: avgRestoreDuration,
            averageFileSize: Int64(avgFileSize),
            averageCompressionRatio: avgCompressionRatio,
            backupSuccessRate: backupSuccessRate * 100.0,
            restoreSuccessRate: restoreSuccessRate * 100.0
        )
    }
    
    // MARK: - Reporting
    
    /// Generates a telemetry report for a given period
    public func generateReport(
        from startDate: Date,
        to endDate: Date
    ) -> TelemetryReport {
        
        let periodEvents = recentEvents.filter { event in
            event.timestamp >= startDate && event.timestamp <= endDate
        }
        
        let backups = periodEvents.filter {
            $0.eventType == .backupCompleted || $0.eventType == .backupFailed
        }
        let restores = periodEvents.filter {
            $0.eventType == .restoreCompleted || $0.eventType == .restoreFailed
        }
        
        let successfulBackups = backups.filter { $0.success }.count
        let failedBackups = backups.count - successfulBackups
        let successfulRestores = restores.filter { $0.success }.count
        let failedRestores = restores.count - successfulRestores
        
        // Calculate metrics for this period
        let avgBackupDuration = backups.compactMap { $0.duration }.average()
        let avgRestoreDuration = restores.compactMap { $0.duration }.average()
        let avgFileSize = backups.compactMap { $0.fileSize }.average()
        
        // Calculate compression ratio for this period
        let compressionRatios = backups.compactMap { event -> Double? in
            guard let compressed = event.fileSize, let uncompressed = event.uncompressedSize, uncompressed > 0 else {
                return nil
            }
            return Double(compressed) / Double(uncompressed)
        }
        let avgCompressionRatio = compressionRatios.isEmpty ? 0.0 : compressionRatios.reduce(0, +) / Double(compressionRatios.count)
        
        let backupSuccessRate = backups.isEmpty ? 0.0 : Double(successfulBackups) / Double(backups.count) * 100.0
        let restoreSuccessRate = restores.isEmpty ? 0.0 : Double(successfulRestores) / Double(restores.count) * 100.0
        
        let metrics = PerformanceMetrics(
            averageBackupDuration: avgBackupDuration,
            averageRestoreDuration: avgRestoreDuration,
            averageFileSize: Int64(avgFileSize),
            averageCompressionRatio: avgCompressionRatio,
            backupSuccessRate: backupSuccessRate,
            restoreSuccessRate: restoreSuccessRate
        )
        
        // Find top errors
        let failedEvents = periodEvents.filter { !$0.success && $0.errorMessage != nil }
        let errorCounts = Dictionary(grouping: failedEvents, by: { $0.errorMessage! })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ErrorCount(error: $0.key, count: $0.value) }
        
        return TelemetryReport(
            generatedAt: Date(),
            periodStart: startDate,
            periodEnd: endDate,
            totalEvents: periodEvents.count,
            totalBackups: backups.count,
            totalRestores: restores.count,
            successfulBackups: successfulBackups,
            failedBackups: failedBackups,
            successfulRestores: successfulRestores,
            failedRestores: failedRestores,
            metrics: metrics,
            topErrors: errorCounts,
            deviceInfo: collectDeviceInfo()
        )
    }
    
    /// Generates a report for the last N days
    public func generateReportForLastDays(_ days: Int) -> TelemetryReport {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        return generateReport(from: startDate, to: endDate)
    }
    
    // MARK: - Data Export
    
    /// Exports telemetry data to JSON
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(recentEvents)
    }
    
    /// Clears all telemetry data
    public func clearAllData() {
        recentEvents.removeAll()
        currentMetrics = nil
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }
    
    // MARK: - Persistence
    
    private func persistEvents() async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recentEvents)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch {
            Logger.backup.error("Failed to persist events: \(error)")
        }
    }
    
    private func loadPersistedEvents() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            recentEvents = try decoder.decode([TelemetryEvent].self, from: data)
        } catch {
            Logger.backup.error("Failed to load events: \(error)")
        }
    }
    
    // MARK: - Device Info
    
    private func collectDeviceInfo() -> DeviceInfo {
        return DeviceInfo(
            model: deviceModel(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        )
    }
    
    private func deviceModel() -> String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        return UIDevice.current.model
        #endif
    }
}

// MARK: - Array Extension

private extension Array where Element == TimeInterval {
    func average() -> TimeInterval {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

private extension Array where Element == Int64 {
    func average() -> Double {
        guard !isEmpty else { return 0 }
        return Double(reduce(0, +)) / Double(count)
    }
}
