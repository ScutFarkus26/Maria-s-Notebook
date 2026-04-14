// SelectiveRestoreService+PayloadHandling.swift
// Payload extraction, decoding, and entity lookup cache management

import Foundation
import CoreData
import OSLog

extension SelectiveRestoreService {
    private static let logger = Logger.backup

    // MARK: - Payload Extraction

    func extractPayload(from url: URL, password: String?) async throws -> BackupPayload {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        let payloadBytes: Data

        if envelope.payload != nil {
            // Direct payload
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .sortedKeys
            payloadBytes = try encoder.encode(envelope.payload!)
        } else if let compressed = envelope.compressedPayload {
            payloadBytes = try codec.decompress(compressed)
        } else if let encrypted = envelope.encryptedPayload {
            guard let password, !password.isEmpty else {
                throw NSError(domain: "SelectiveRestoreService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Backup is encrypted. Please provide a password."
                ])
            }
            let decrypted = try codec.decrypt(encrypted, password: password)
            if envelope.manifest.compression != nil {
                payloadBytes = try codec.decompress(decrypted)
            } else {
                payloadBytes = decrypted
            }
        } else {
            throw NSError(domain: "SelectiveRestoreService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Backup file missing payload."
            ])
        }

        return try decoder.decode(BackupPayload.self, from: payloadBytes)
    }

    // MARK: - Cache Helpers

    /// Helper to fetch and cache entity IDs for a given type.
    /// Core Data entities have optional `id: UUID?`, so we compactMap to filter out nils.
    func cacheEntityIDs<T: NSManagedObject>(
        _ type: T.Type, key: String, idKeyPath: KeyPath<T, UUID?>, in context: NSManagedObjectContext
    ) {
        do {
            let entities = try context.fetch(T.fetchRequest() as! NSFetchRequest<T>)
            existingIDSets[key] = Set(entities.compactMap { $0[keyPath: idKeyPath] })
        } catch {
            let desc = error.localizedDescription
            Self.logger.warning("Failed to cache entity IDs for \(key, privacy: .public): \(desc, privacy: .public)")
            existingIDSets[key] = []
        }
    }

    /// Helper to fetch and cache entities with full objects for relationships.
    /// Core Data entities have optional `id: UUID?`, so we compactMap to filter out nils.
    func cacheDictionary<T: NSManagedObject>(
        _ type: T.Type, idKeyPath: KeyPath<T, UUID?>, in context: NSManagedObjectContext
    ) -> [UUID: T] {
        do {
            let entities = try context.fetch(T.fetchRequest() as! NSFetchRequest<T>)
            return Dictionary(uniqueKeysWithValues: entities.compactMap { e in
                e[keyPath: idKeyPath].map { ($0, e) }
            })
        } catch {
            let desc = error.localizedDescription
            Self.logger.warning("Failed to cache dictionary for \(T.self, privacy: .public): \(desc, privacy: .public)")
            return [:]
        }
    }

    /// Helper to get cached ID set.
    func getCachedIDs(_ key: String) -> Set<UUID> {
        return existingIDSets[key] ?? []
    }

    /// Creates an existence-check closure that uses the cached ID set for O(1) lookup
    /// and fetches the actual entity only when a match is found.
    func cachedExistenceCheck<T: NSManagedObject>(
        key: String,
        entityName: String,
        in context: NSManagedObjectContext
    ) -> BackupEntityImporter.EntityExistsCheck<T> {
        return { [self] id in
            guard self.getCachedIDs(key).contains(id) else { return nil }
            let request = NSFetchRequest<T>(entityName: entityName)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            return try context.fetch(request).first
        }
    }

    /// Pre-builds lookup caches for all entity types to enable O(1) existence checks.
    /// This is much faster than querying the database for each entity.
    func buildExistingIDCaches(in context: NSManagedObjectContext) {
        // Build lookup dictionaries for entities needed for relationship linking
        studentsByID = cacheDictionary(CDStudent.self, idKeyPath: \.id, in: context)
        lessonsByID = cacheDictionary(CDLesson.self, idKeyPath: \.id, in: context)
        topicsByID = cacheDictionary(CDCommunityTopicEntity.self, idKeyPath: \.id, in: context)
        // templateWeeksByID removed — CDProjectTemplateWeek is deprecated

        // Build ID sets for simple existence checks
        // LegacyPresentation removed — entity IDs cached via CDLessonAssignment below
        cacheEntityIDs(CDNote.self, key: "notes", idKeyPath: \.id, in: context)
        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        cacheEntityIDs(CDNonSchoolDay.self, key: "nonSchoolDays", idKeyPath: \.id, in: context)
        cacheEntityIDs(CDSchoolDayOverride.self, key: "schoolDayOverrides", idKeyPath: \.id, in: context)
        cacheEntityIDs(CDStudentMeeting.self, key: "studentMeetings", idKeyPath: \.id, in: context)
        cacheEntityIDs(CDLessonAssignment.self, key: "lessonAssignments", idKeyPath: \.id, in: context)
        cacheEntityIDs(CDProposedSolutionEntity.self, key: "proposedSolutions", idKeyPath: \.id, in: context)
        cacheEntityIDs(CDCommunityAttachmentEntity.self, key: "communityAttachments", idKeyPath: \.id, in: context)
        cacheEntityIDs(CDAttendanceRecord.self, key: "attendanceRecords", idKeyPath: \.id, in: context)
        cacheEntityIDs(CDWorkCompletionRecord.self, key: "workCompletionRecords", idKeyPath: \.id, in: context)
        cacheEntityIDs(CDProject.self, key: "projects", idKeyPath: \.id, in: context)
        cacheEntityIDs(CDProjectRole.self, key: "projectRoles", idKeyPath: \.id, in: context)
        // CDProjectAssignmentTemplate and CDProjectWeekRoleAssignment caches removed — deprecated
        cacheEntityIDs(CDProjectSession.self, key: "projectSessions", idKeyPath: \.id, in: context)
    }

    /// Clears the lookup caches to free memory after restore is complete
    func clearIDCaches() {
        studentsByID = [:]
        lessonsByID = [:]
        topicsByID = [:]
        existingIDSets = [:]
    }
}
