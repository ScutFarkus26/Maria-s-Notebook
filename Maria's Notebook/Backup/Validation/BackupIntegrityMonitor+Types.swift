import Foundation

// MARK: - Types extracted from BackupIntegrityMonitor

extension BackupIntegrityMonitor {

    public enum BackupHealth: Sendable, CustomStringConvertible {
        case healthy
        case warning(String)
        case critical(String)

        public var isHealthy: Bool {
            if case .healthy = self { return true }
            return false
        }

        public var message: String? {
            switch self {
            case .healthy: return nil
            case .warning(let msg), .critical(let msg): return msg
            }
        }

        public var description: String {
            switch self {
            case .healthy: return "healthy"
            case .warning(let msg): return "warning: \(msg)"
            case .critical(let msg): return "critical: \(msg)"
            }
        }
    }

    public struct IntegrityReport: Sendable {
        public let timestamp: Date
        public let health: BackupHealth
        public let totalBackups: Int
        public let healthyBackups: Int
        public let corruptedBackups: Int
        public let lastBackupDate: Date?
        public let daysSinceLastBackup: Int?
        public let oldestBackupDate: Date?
        public let totalBackupSize: Int64
        public let issues: [String]
        public let recommendations: [String]

        public var formattedTotalSize: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            return formatter.string(fromByteCount: totalBackupSize)
        }
    }

    public struct BackupVerificationResult: Identifiable, Sendable {
        public let id: UUID
        public let url: URL
        public let fileName: String
        public let isValid: Bool
        public let errorMessage: String?
        public let checksumValid: Bool?
        public let formatVersion: Int?
        public let createdAt: Date?
        public let fileSize: Int64
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let backupIntegrityIssuesDetected = Notification.Name("BackupIntegrityIssuesDetected")
}
