import Foundation
import SwiftData
import OSLog

// MARK: - Utility & Helper Methods

extension BackupService {
    private static let logger = Logger.backup

    // MARK: - Security-Scoped Resource Access

    func withSecurityScopedResource<T>(_ url: URL, operation: () throws -> T) rethrows -> T {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    // MARK: - Load & Decode Pipeline

    func loadAndDecodeBackup(
        from url: URL,
        password: String?,
        progress: @escaping ProgressCallback
    ) throws -> (envelope: BackupEnvelope, payload: BackupPayload) {
        progress(0.05, "Reading file\u{2026}")
        let data = try Data(contentsOf: url)

        try validateBackupData(data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decodeEnvelope(from: data, decoder: decoder)

        let payloadBytes = try extractPayloadBytes(
            from: envelope,
            password: password,
            progress: progress
        )

        try validateChecksum(payloadBytes, against: envelope.manifest.sha256, progress: progress)

        let payload = try decodePayload(from: payloadBytes, decoder: decoder)

        return (envelope, payload)
    }

    // MARK: - Entity Fetch

    func fetchOne<T: PersistentModel>(_ type: T.Type, id: UUID, using context: ModelContext) throws -> T? {
        return try BackupFetchHelper.fetchOne(type, id: id, using: context)
    }

    // MARK: - Preferences (delegated to BackupPreferencesService)

    func buildPreferencesDTO() -> PreferencesDTO {
        BackupPreferencesService.buildPreferencesDTO()
    }

    func applyPreferencesDTO(_ dto: PreferencesDTO) {
        BackupPreferencesService.applyPreferencesDTO(dto)
    }

    // MARK: - Data Management

    func deleteAll(modelContext: ModelContext) throws {
        for type in BackupEntityRegistry.allTypes {
            do {
                try modelContext.delete(model: type)
            } catch {
                let desc = error.localizedDescription
                Self.logger.warning("Failed to delete \(type, privacy: .public): \(desc, privacy: .public)")
            }
        }
        try modelContext.save()
    }

    func deduplicatePayload(_ payload: BackupPayload) -> BackupPayload {
        BackupPayloadDeduplicator.deduplicate(payload)
    }
}
