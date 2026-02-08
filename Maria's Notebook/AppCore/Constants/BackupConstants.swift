import Foundation

/// Centralized constants for backup and restore operations
enum BackupConstants {
    // MARK: - Performance Configuration
    
    /// Default batch size for streaming backup operations
    static let streamingBatchSize = 500
    
    /// Chunk size for delta sync operations (64 KB)
    static let deltaChunkSize = 64 * 1024
    
    /// Threshold for delta compression effectiveness (0.8 = 80%)
    /// Below this ratio, delta sync is considered inefficient
    static let deltaCompressionThreshold = 0.8
    
    // MARK: - Conflict Detection Thresholds
    
    /// Time window (in seconds) to detect simultaneous modifications
    /// Modifications within this window may indicate conflicts
    static let simultaneousModificationThreshold: TimeInterval = 60
    
    /// Entity count difference threshold for conflict detection (0.1 = 10%)
    /// Differences above this threshold may indicate data conflicts
    static let entityDiffThreshold = 0.1
    
    // MARK: - UI Constants
    
    /// Maximum days displayed in calendar grid views
    static let maxCalendarDaysInGrid = 14
    
    /// Success rate threshold for telemetry (95%)
    static let telemetrySuccessThreshold = 95
    
    /// Warning threshold for telemetry (80%)
    static let telemetryWarningThreshold = 80
}
