import Foundation
import CoreData
import SwiftUI

// MARK: - Import Methods

extension EnhancedBackupService {

    /// Enhanced import with validation and transactional support
    public func importBackup(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        importMode: ImportMode? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> EnhancedRestoreResult {

        let startTime = Date()

        // Extract and validate payload first
        progress(0.0, "Loading backup file\u{2026}")
        let payload = try await extractPayload(from: url, password: password)

        // Pre-validation
        progress(0.1, "Validating backup data\u{2026}")
        let validationResult = try await validationService.validate(
            payload: payload,
            against: viewContext,
            mode: mode
        )

        if !validationResult.canProceed {
            throw NSError(
                domain: "EnhancedBackupService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Backup validation failed with \(validationResult.errors.count) critical errors"
                ]
            )
        }

        // Perform import using standard mode
        let summary = try await backupService.importBackup(
            viewContext: viewContext,
            from: url,
            mode: mode,
            password: password,
            progress: progress
        )

        return EnhancedRestoreResult(
            success: true,
            importMode: .standard,
            importedEntities: summary.entityCounts,
            failedEntities: [:],
            validationResult: validationResult,
            errors: [],
            warnings: validationResult.warnings.map(\.message),
            duration: Date().timeIntervalSince(startTime),
            restorePointURL: nil
        )
    }

    // MARK: - Preview

    public func previewImport(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> EnhancedRestorePreview {

        let preview = try await backupService.previewImport(
            viewContext: viewContext,
            from: url,
            mode: mode,
            password: password,
            progress: progress
        )

        // Add validation results
        let payload = try await extractPayload(from: url, password: password)
        let validation = try await validationService.validate(
            payload: payload,
            against: viewContext,
            mode: mode
        )

        // Detect conflicts between backup data and current database state
        let conflicts = try await detectRestoreConflicts(
            payload: payload,
            viewContext: viewContext,
            mode: mode
        )

        return EnhancedRestorePreview(
            preview: preview,
            validation: validation,
            conflicts: conflicts
        )
    }
}
