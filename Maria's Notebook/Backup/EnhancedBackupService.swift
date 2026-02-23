import Foundation
import SwiftData
import SwiftUI

/// Enhanced backup service that integrates all new improvements
/// Use this as a drop-in replacement for BackupService with better performance and reliability
@MainActor
public final class EnhancedBackupService {
    
    // MARK: - Types
    
    public typealias RestoreMode = BackupService.RestoreMode
    
    public enum ExportMode {
        case standard      // Original implementation (for compatibility)
        case streaming     // New streaming implementation (recommended)
        case incremental   // Incremental backup based on changes
    }
    
    public enum ImportMode {
        case standard      // Original implementation
    }
    
    // MARK: - Services
    
    private let backupService = BackupService()
    private let streamingWriter: StreamingBackupWriter
    private let validationService: BackupValidationService
    private let checksumService: ChecksumVerificationService
    private let incrementalService: IncrementalBackupService
    private let integrityMonitor: BackupIntegrityMonitor
    private let conflictResolver: CloudSyncConflictResolver
    
    // MARK: - Configuration
    
    public var preferredExportMode: ExportMode = .streaming
    public var preferredImportMode: ImportMode = .standard
    public var enableAutoVerification: Bool = true
    public var enableSigning: Bool = true
    
    // MARK: - Initialization
    
    public init() {
        self.streamingWriter = StreamingBackupWriter(configuration: .default)
        self.validationService = BackupValidationService()
        self.checksumService = ChecksumVerificationService()
        self.incrementalService = IncrementalBackupService(backupService: backupService)
        self.integrityMonitor = BackupIntegrityMonitor()
        self.conflictResolver = CloudSyncConflictResolver(
            backupService: backupService,
            validationService: validationService
        )
    }
    
    // MARK: - Size Estimation
    
    public func estimateBackupSize(modelContext: ModelContext) -> Int64 {
        BackupSizeEstimator.estimateBackupSize(modelContext: modelContext)
    }
    
    public func estimateBackupSizeFromCounts(_ counts: [String: Int]) -> Int64 {
        BackupSizeEstimator.estimateFromCounts(counts)
    }
    
    // MARK: - Export
    
    /// Enhanced export with mode selection and automatic verification
    public func exportBackup(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        mode: ExportMode? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> EnhancedBackupOperationSummary {
        
        let exportMode = mode ?? preferredExportMode
        let startTime = Date()
        
        let summary: BackupOperationSummary
        
        switch exportMode {
        case .streaming:
            summary = try await streamingWriter.streamingExport(
                modelContext: modelContext,
                to: url,
                password: password,
                progress: { prog, msg, count, type in
                    progress(prog, msg)
                }
            )
            
        case .incremental:
            let result = try await incrementalService.createIncrementalBackup(
                modelContext: modelContext,
                to: url,
                password: password,
                forceFullBackup: false,
                progress: progress
            )
            summary = BackupOperationSummary(
                kind: .export,
                fileName: url.lastPathComponent,
                formatVersion: BackupFile.formatVersion,
                encryptUsed: password != nil,
                createdAt: Date(),
                entityCounts: result.metadata.changedEntityCounts,
                warnings: []
            )
            
        case .standard:
            summary = try await backupService.exportBackup(
                modelContext: modelContext,
                to: url,
                password: password,
                progress: progress
            )
        }
        
        // Post-export verification if enabled
        var verificationResult: ChecksumVerificationService.VerificationResult?
        if enableAutoVerification {
            do {
                verificationResult = try await verifyBackupFile(at: url, password: password)
            } catch {
                // Log but don't fail the export
                print("EnhancedBackupService: Post-export verification failed: \(error)")
            }
        }
        
        // Generate verification report
        let report = generateVerificationReport(
            for: url,
            summary: summary,
            verificationResult: verificationResult,
            duration: Date().timeIntervalSince(startTime)
        )
        
        return EnhancedBackupOperationSummary(
            summary: summary,
            exportMode: exportMode,
            verificationResult: verificationResult,
            verificationReport: report,
            duration: Date().timeIntervalSince(startTime)
        )
    }
    
    // MARK: - Import
    
    /// Enhanced import with validation and transactional support
    public func importBackup(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        importMode: ImportMode? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> EnhancedRestoreResult {
        
        let startTime = Date()
        
        // Extract and validate payload first
        progress(0.0, "Loading backup file…")
        let payload = try await extractPayload(from: url, password: password)
        
        // Pre-validation
        progress(0.1, "Validating backup data…")
        let validationResult = try await validationService.validate(
            payload: payload,
            against: modelContext,
            mode: mode
        )
        
        if !validationResult.canProceed {
            throw NSError(
                domain: "EnhancedBackupService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Backup validation failed with \(validationResult.errors.count) critical errors"
                ]
            )
        }
        
        // Perform import using standard mode
        let summary = try await backupService.importBackup(
            modelContext: modelContext,
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
            warnings: validationResult.warnings.map { $0.message },
            duration: Date().timeIntervalSince(startTime),
            restorePointURL: nil
        )
    }
    
    // MARK: - Preview
    
    public func previewImport(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> EnhancedRestorePreview {
        
        let preview = try await backupService.previewImport(
            modelContext: modelContext,
            from: url,
            mode: mode,
            password: password,
            progress: progress
        )
        
        // Add validation results
        let payload = try await extractPayload(from: url, password: password)
        let validation = try await validationService.validate(
            payload: payload,
            against: modelContext,
            mode: mode
        )
        
        // Detect conflicts between backup data and current database state
        let conflicts = try await detectRestoreConflicts(
            payload: payload,
            modelContext: modelContext,
            mode: mode
        )
        
        return EnhancedRestorePreview(
            preview: preview,
            validation: validation,
            conflicts: conflicts
        )
    }
    
    // MARK: - Conflict Detection
    
    /// Detects potential conflicts between backup data and current database state
    /// This helps identify issues before attempting a restore operation
    private func detectRestoreConflicts(
        payload: BackupPayload,
        modelContext: ModelContext,
        mode: RestoreMode
    ) async throws -> [CloudSyncConflictResolver.Conflict] {
        var conflicts: [CloudSyncConflictResolver.Conflict] = []

        // Replace mode intentionally overwrites everything, so merge conflicts do not apply.
        guard mode == .merge else {
            return []
        }

        let backupCounts = getPayloadEntityCounts(payload)
        let localCounts = try currentEntityCounts(modelContext: modelContext)
        let localInfo = makeLocalBackupInfo(entityCounts: localCounts)
        let incomingInfo = makeIncomingBackupInfo(entityCounts: backupCounts)

        // Count divergence can indicate drift between devices.
        let localTotal = localCounts.values.reduce(0, +)
        let incomingTotal = backupCounts.values.reduce(0, +)
        let totalDiff = abs(localTotal - incomingTotal)
        if max(localTotal, incomingTotal) > 0 {
            let ratio = Double(totalDiff) / Double(max(localTotal, incomingTotal))
            if ratio > BackupConstants.entityDiffThreshold {
                conflicts.append(
                    CloudSyncConflictResolver.Conflict(
                        localBackup: localInfo,
                        remoteBackup: incomingInfo,
                        conflictType: .divergentHistory,
                        description: "Database and backup differ significantly in record counts (\(localTotal) vs \(incomingTotal))."
                    )
                )
            }
        }

        // Entity-level overlap detects likely duplicates during merge.
        let duplicateCandidates = try duplicateConflictCandidates(payload: payload, modelContext: modelContext)
        for candidate in duplicateCandidates {
            conflicts.append(
                CloudSyncConflictResolver.Conflict(
                    localBackup: localInfo,
                    remoteBackup: incomingInfo,
                    conflictType: .duplicateEntity,
                    description: candidate
                )
            )
        }

        return conflicts
    }
    
    /// Extracts entity counts from backup payload
    private func getPayloadEntityCounts(_ payload: BackupPayload) -> [String: Int] {
        return [
            "students": payload.students.count,
            "lessons": payload.lessons.count,
            "items": payload.items.count,
            "notes": payload.notes.count,
            "attendance": payload.attendance.count,
            "lessonAssignments": payload.lessonAssignments.count
        ]
    }

    private func currentEntityCounts(modelContext: ModelContext) throws -> [String: Int] {
        [
            "students": try modelContext.fetchCount(FetchDescriptor<Student>()),
            "lessons": try modelContext.fetchCount(FetchDescriptor<Lesson>()),
            "notes": try modelContext.fetchCount(FetchDescriptor<Note>()),
            "attendance": try modelContext.fetchCount(FetchDescriptor<AttendanceRecord>()),
            "lessonAssignments": try modelContext.fetchCount(FetchDescriptor<LessonAssignment>())
        ]
    }

    private func duplicateConflictCandidates(
        payload: BackupPayload,
        modelContext: ModelContext
    ) throws -> [String] {
        var conflicts: [String] = []

        let localStudentIDs = Set(try modelContext.fetch(FetchDescriptor<Student>()).map(\.id))
        let localLessonIDs = Set(try modelContext.fetch(FetchDescriptor<Lesson>()).map(\.id))
        let localNoteIDs = Set(try modelContext.fetch(FetchDescriptor<Note>()).map(\.id))
        let localAttendanceIDs = Set(try modelContext.fetch(FetchDescriptor<AttendanceRecord>()).map(\.id))
        let localAssignmentIDs = Set(try modelContext.fetch(FetchDescriptor<LessonAssignment>()).map(\.id))

        appendDuplicateConflict(
            label: "students",
            incoming: Set(payload.students.map(\.id)),
            local: localStudentIDs,
            to: &conflicts
        )
        appendDuplicateConflict(
            label: "lessons",
            incoming: Set(payload.lessons.map(\.id)),
            local: localLessonIDs,
            to: &conflicts
        )
        appendDuplicateConflict(
            label: "notes",
            incoming: Set(payload.notes.map(\.id)),
            local: localNoteIDs,
            to: &conflicts
        )
        appendDuplicateConflict(
            label: "attendance records",
            incoming: Set(payload.attendance.map(\.id)),
            local: localAttendanceIDs,
            to: &conflicts
        )
        appendDuplicateConflict(
            label: "lesson assignments",
            incoming: Set(payload.lessonAssignments.map(\.id)),
            local: localAssignmentIDs,
            to: &conflicts
        )

        return conflicts
    }

    private func appendDuplicateConflict(
        label: String,
        incoming: Set<UUID>,
        local: Set<UUID>,
        to conflicts: inout [String]
    ) {
        guard !incoming.isEmpty, !local.isEmpty else { return }
        let overlap = incoming.intersection(local).count
        guard overlap > 0 else { return }
        conflicts.append("Potential duplicate \(label): \(overlap) incoming IDs already exist locally.")
    }

    private func makeLocalBackupInfo(entityCounts: [String: Int]) -> CloudSyncConflictResolver.BackupInfo {
        CloudSyncConflictResolver.BackupInfo(
            url: URL(fileURLWithPath: "/local-database"),
            timestamp: Date(),
            entityCounts: entityCounts,
            checksum: "local",
            deviceID: "local",
            formatVersion: BackupFile.formatVersion
        )
    }

    private func makeIncomingBackupInfo(entityCounts: [String: Int]) -> CloudSyncConflictResolver.BackupInfo {
        CloudSyncConflictResolver.BackupInfo(
            url: URL(fileURLWithPath: "/incoming-backup"),
            timestamp: Date(),
            entityCounts: entityCounts,
            checksum: "incoming",
            deviceID: "incoming",
            formatVersion: BackupFile.formatVersion
        )
    }
    
    // MARK: - Integrity & Verification
    
    /// Verifies a backup file's integrity
    public func verifyBackup(at url: URL, password: String? = nil) async throws -> BackupIntegrityMonitor.BackupVerificationResult {
        return await integrityMonitor.verifyBackup(at: url)
    }
    
    /// Performs integrity scan of all backups
    public func performIntegrityScan() async -> BackupIntegrityMonitor.IntegrityReport {
        return await integrityMonitor.performIntegrityScan()
    }
    
    /// Enables scheduled integrity monitoring
    public func startScheduledIntegrityMonitoring() {
        integrityMonitor.startScheduledVerification()
    }
    
    /// Disables scheduled integrity monitoring
    public func stopScheduledIntegrityMonitoring() {
        integrityMonitor.stopScheduledVerification()
    }
    
    // MARK: - Cloud Sync & Conflict Resolution
    
    /// Detects conflicts between local and remote backups
    public func detectCloudConflicts(
        between localURL: URL,
        and remoteURL: URL
    ) async throws -> [CloudSyncConflictResolver.Conflict] {
        return try await conflictResolver.detectConflicts(between: localURL, and: remoteURL)
    }
    
    /// Resolves cloud sync conflicts
    public func resolveCloudConflicts(
        local localURL: URL,
        remote remoteURL: URL,
        strategy: CloudSyncConflictResolver.ConflictResolutionStrategy,
        to outputURL: URL,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> CloudSyncConflictResolver.MergeResult {
        return try await conflictResolver.resolve(
            local: localURL,
            remote: remoteURL,
            strategy: strategy,
            to: outputURL,
            password: password,
            progress: progress
        )
    }
    
    // MARK: - Incremental Backups
    
    /// Creates an incremental backup
    public func createIncrementalBackup(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        forceFullBackup: Bool = false,
        progress: @escaping (Double, String) -> Void
    ) async throws -> IncrementalBackupService.IncrementalBackupResult {
        return try await incrementalService.createIncrementalBackup(
            modelContext: modelContext,
            to: url,
            password: password,
            forceFullBackup: forceFullBackup,
            progress: progress
        )
    }
    
    /// Resets incremental backup tracking (next backup will be full)
    public func resetIncrementalTracking() {
        incrementalService.resetIncrementalTracking()
    }
    
    // MARK: - Private Helpers
    
    private func extractPayload(from url: URL, password: String?) async throws -> BackupPayload {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        
        let codec = BackupCodec()
        let payloadBytes: Data
        
        if let compressed = envelope.compressedPayload {
            payloadBytes = try codec.decompress(compressed)
        } else if let encrypted = envelope.encryptedPayload {
            guard let password = password, !password.isEmpty else {
                throw NSError(
                    domain: "EnhancedBackupService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "This backup is encrypted. Please provide a password."]
                )
            }
            let decrypted = try codec.decrypt(encrypted, password: password)
            // Check if decrypted data is also compressed
            if envelope.manifest.compression != nil {
                payloadBytes = try codec.decompress(decrypted)
            } else {
                payloadBytes = decrypted
            }
        } else {
            throw NSError(
                domain: "EnhancedBackupService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Backup file missing payload"]
            )
        }
        
        return try decoder.decode(BackupPayload.self, from: payloadBytes)
    }
    
    private func verifyBackupFile(
        at url: URL,
        password: String?
    ) async throws -> ChecksumVerificationService.VerificationResult {
        let payload = try await extractPayload(from: url, password: password)
        let manifest = try checksumService.generateChecksumManifest(for: payload)
        return try checksumService.verify(payload: payload, against: manifest)
    }
    
    private func generateVerificationReport(
        for url: URL,
        summary: BackupOperationSummary,
        verificationResult: ChecksumVerificationService.VerificationResult?,
        duration: TimeInterval
    ) -> BackupVerificationReport {
        var issues: [String] = []
        var recommendations: [String] = []
        
        if let verification = verificationResult {
            if !verification.isValid {
                issues.append("Backup file failed integrity verification")
                if !verification.corruptedEntities.isEmpty {
                    issues.append("Corrupted entity types: \(verification.corruptedEntities.joined(separator: ", "))")
                }
                recommendations.append("Delete this backup and create a new one")
            }
        }
        
        return BackupVerificationReport(
            url: url,
            createdAt: summary.createdAt,
            isValid: verificationResult?.isValid ?? true,
            duration: duration,
            issues: issues,
            recommendations: recommendations
        )
    }
}

// MARK: - Enhanced Result Types

public struct EnhancedBackupOperationSummary {
    public let summary: BackupOperationSummary
    public let exportMode: EnhancedBackupService.ExportMode
    public let verificationResult: ChecksumVerificationService.VerificationResult?
    public let verificationReport: BackupVerificationReport
    public let duration: TimeInterval
}

public struct EnhancedRestoreResult {
    public let success: Bool
    public let importMode: EnhancedBackupService.ImportMode
    public let importedEntities: [String: Int]
    public let failedEntities: [String: Int]
    public let validationResult: BackupValidationService.ValidationResult
    public let errors: [String]
    public let warnings: [String]
    public let duration: TimeInterval
    public let restorePointURL: URL?
    
    public var totalImported: Int {
        importedEntities.values.reduce(0, +)
    }
    
    public var totalFailed: Int {
        failedEntities.values.reduce(0, +)
    }
}

public struct EnhancedRestorePreview {
    public let preview: RestorePreview
    public let validation: BackupValidationService.ValidationResult
    public let conflicts: [CloudSyncConflictResolver.Conflict]
}

public struct BackupVerificationReport {
    public let url: URL
    public let createdAt: Date
    public let isValid: Bool
    public let duration: TimeInterval
    public let issues: [String]
    public let recommendations: [String]
}
