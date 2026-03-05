import Foundation
import SwiftData
import OSLog

// MARK: - Check-In Migration Service

/// Service providing legacy check-in migration utilities and backward compatibility.
/// Part of the "Strangler Fig" migration pattern to consolidate check-in systems.
///
/// Migration Phases:
/// - Phase 1: Backfill all legacy check-ins → WorkCheckIns (scheduled status) [COMPLETE]
/// - Phase 2-5: Gradual transition of write/read paths [COMPLETE]
/// - Phase 6: Complete removal of legacy model [COMPLETE]
///
/// NOTE: Legacy check-in model has been removed in Phase 6.
/// This service is retained for the mapReasonToPurpose() utility function.
///
/// References:
/// - Docs/Work_Models_Best_Practices.md
/// - Docs/Work_Completion_System_Migration.md (pattern reference)
enum CheckInMigrationService {
    private static let logger = Logger.migration

    // MARK: - Legacy Check-In Reason Enum

    /// Legacy check-in reason enum (preserved for mapping purposes).
    /// This enum is no longer used in the data model.
    enum CheckInReason: String, Codable, CaseIterable, Identifiable {
        case progressCheck
        case dueDate
        case assessment
        case followUp
        case studentRequest
        case other
        
        var id: String { rawValue }
    }
    
    // MARK: - Reason Mapping

    /// Maps legacy check-in reason enum to WorkCheckIn purpose string.
    /// This preserves the semantic meaning during migration.
    static func mapReasonToPurpose(_ reason: CheckInReason?) -> String {
        guard let reason = reason else { return "Other" }
        
        switch reason {
        case .progressCheck:
            return "Progress Check"
        case .dueDate:
            return "Due Date"
        case .assessment:
            return "Assessment"
        case .followUp:
            return "Follow Up"
        case .studentRequest:
            return "Student Request"
        case .other:
            return "Other"
        }
    }
    
    // MARK: - Backfill Migration (Phase 1) - COMPLETED

    // PHASE 6 NOTE: This method has been disabled because legacy check-in model has been removed.
    // The backfill migration was completed in Phase 1 and is no longer needed.
    // This code is preserved for historical reference only.
    /*
    @MainActor
    static func backfillWorkCheckInsFromLegacyCheckIns(using context: ModelContext) {
        // Migration already complete - legacy model removed in Phase 6
        logger.info("Backfill already completed - legacy model removed")
    }
    */

    // MARK: - Phase 6: Final Cleanup - COMPLETED

    // PHASE 6 NOTE: Cleanup methods have been disabled because legacy check-in model has been removed.
    // All migration phases are complete. This code is preserved for historical reference only.
    /*
    @MainActor
    static func deleteAllLegacyCheckIns(using context: ModelContext) {
        // Migration already complete - legacy model removed in Phase 6
        logger.info("Cleanup already completed - legacy model removed")
    }
    */
}
