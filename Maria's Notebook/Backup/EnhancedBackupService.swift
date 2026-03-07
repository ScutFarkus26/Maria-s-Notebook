import Foundation
import SwiftData
import SwiftUI

/// Enhanced backup service that integrates all new improvements
/// Use this as a drop-in replacement for BackupService with better performance and reliability
///
/// Split into multiple files for maintainability:
/// - EnhancedBackupService.swift (this file) - Core service, export, verification, cloud sync
/// - EnhancedBackupTypes.swift - Result types (EnhancedBackupOperationSummary, etc.)
/// - EnhancedBackupService+ConflictDetection.swift - Conflict detection helpers
/// - EnhancedBackupService+Import.swift - Import and preview methods
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

    let backupService = BackupService()
    let streamingWriter: StreamingBackupWriter
    let validationService: BackupValidationService
    let checksumService: ChecksumVerificationService
    let incrementalService: IncrementalBackupService
    let integrityMonitor: BackupIntegrityMonitor
    let conflictResolver: CloudSyncConflictResolver

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

    // Enhanced export with mode selection and automatic verification
    // swiftlint:disable:next function_body_length
    public func exportBackup(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        mode: ExportMode? = nil,
        progress: @escaping BackupService.ProgressCallback
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
                progress: { prog, msg, _, _ in
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

    // MARK: - Integrity & Verification

    /// Verifies a backup file's integrity
    public func verifyBackup(
        at url: URL, password: String? = nil
    ) async throws -> BackupIntegrityMonitor.BackupVerificationResult {
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
        progress: @escaping BackupService.ProgressCallback
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
        progress: @escaping BackupService.ProgressCallback
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

    func extractPayload(from url: URL, password: String?) async throws -> BackupPayload {
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
