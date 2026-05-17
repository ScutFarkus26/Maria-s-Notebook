import Foundation
import CoreData
import OSLog

// MARK: - Utility & Helper Methods

extension BackupService {
    private static let logger = Logger.backup

    // MARK: - Security-Scoped CDResource Access

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
        let log = Logger.backup
        do {
            progress(0.05, "Reading file\u{2026}")
            let data = try Data(contentsOf: url)
            log.info("loadAndDecodeBackup: read \(data.count) bytes from \(url.lastPathComponent, privacy: .public)")

            try validateBackupData(data)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decodeEnvelope(from: data, decoder: decoder)
            log.info("loadAndDecodeBackup: envelope format=\(envelope.formatVersion, privacy: .public)")

            let payloadBytes = try extractPayloadBytes(
                from: envelope,
                password: password,
                progress: progress
            )
            log.info("loadAndDecodeBackup: extracted \(payloadBytes.count) payload bytes")

            try validateChecksum(payloadBytes, against: envelope.manifest.sha256, progress: progress)

            let payload = try decodePayload(from: payloadBytes, decoder: decoder)
            log.info("loadAndDecodeBackup: decoded payload with \(payload.lessons.count) lessons")

            return (envelope, payload)
        } catch {
            let ns = error as NSError
            log.error("loadAndDecodeBackup failed: domain=\(ns.domain, privacy: .public) code=\(ns.code) desc=\(ns.localizedDescription, privacy: .public) underlying=\(String(describing: ns.userInfo[NSUnderlyingErrorKey]), privacy: .public)")
            throw error
        }
    }

    // MARK: - Entity Fetch

    func fetchOne<T: NSManagedObject>(_ type: T.Type, id: UUID, using context: NSManagedObjectContext) throws -> T? {
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

    func deleteAll(viewContext: NSManagedObjectContext) throws {
        let model = viewContext.persistentStoreCoordinator?.managedObjectModel
        for type in BackupEntityRegistry.allTypes {
            do {
                let entityName = String(describing: type).replacingOccurrences(of: "CD", with: "")
                // Skip types whose entity doesn't exist in the model
                guard model?.entitiesByName[entityName] != nil else { continue }
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                deleteRequest.resultType = .resultTypeObjectIDs
                let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                        into: [viewContext]
                    )
                }
            } catch {
                let desc = error.localizedDescription
                Self.logger.warning("Failed to delete \(type, privacy: .public): \(desc, privacy: .public)")
            }
        }
    }

    func deduplicatePayload(_ payload: BackupPayload) -> BackupPayload {
        BackupPayloadDeduplicator.deduplicate(payload)
    }
}
