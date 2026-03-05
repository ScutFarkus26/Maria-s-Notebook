// SelectiveRestoreService+PayloadHandling.swift
// Payload extraction, decoding, and entity lookup cache management

import Foundation
import SwiftData

extension SelectiveRestoreService {

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
            guard let password = password, !password.isEmpty else {
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
    func cacheEntityIDs<T: PersistentModel & Identifiable>(_ type: T.Type, key: String, in context: ModelContext) where T.ID == UUID {
        do {
            let entities = try context.fetch(FetchDescriptor<T>())
            existingIDSets[key] = Set(entities.map { $0.id })
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to cache entity IDs for \(key): \(error)")
            existingIDSets[key] = []
        }
    }

    /// Helper to fetch and cache entities with full objects for relationships.
    func cacheDictionary<T: PersistentModel & Identifiable>(_ type: T.Type, in context: ModelContext) -> [UUID: T] where T.ID == UUID {
        do {
            let entities = try context.fetch(FetchDescriptor<T>())
            return entities.toDictionary(by: \.id)
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to cache dictionary for \(T.self): \(error)")
            return [:]
        }
    }

    /// Helper to get cached ID set.
    func getCachedIDs(_ key: String) -> Set<UUID> {
        return existingIDSets[key] ?? []
    }

    /// Pre-builds lookup caches for all entity types to enable O(1) existence checks.
    /// This is much faster than querying the database for each entity.
    func buildExistingIDCaches(in context: ModelContext) {
        // Build lookup dictionaries for entities needed for relationship linking
        studentsByID = cacheDictionary(Student.self, in: context)
        lessonsByID = cacheDictionary(Lesson.self, in: context)
        topicsByID = cacheDictionary(CommunityTopic.self, in: context)
        templateWeeksByID = cacheDictionary(ProjectTemplateWeek.self, in: context)

        // Build ID sets for simple existence checks
        // LegacyPresentation removed — entity IDs cached via LessonAssignment below
        cacheEntityIDs(Note.self, key: "notes", in: context)
        // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn
        cacheEntityIDs(NonSchoolDay.self, key: "nonSchoolDays", in: context)
        cacheEntityIDs(SchoolDayOverride.self, key: "schoolDayOverrides", in: context)
        cacheEntityIDs(StudentMeeting.self, key: "studentMeetings", in: context)
        cacheEntityIDs(LessonAssignment.self, key: "lessonAssignments", in: context)
        cacheEntityIDs(ProposedSolution.self, key: "proposedSolutions", in: context)
        cacheEntityIDs(CommunityAttachment.self, key: "communityAttachments", in: context)
        cacheEntityIDs(AttendanceRecord.self, key: "attendanceRecords", in: context)
        cacheEntityIDs(WorkCompletionRecord.self, key: "workCompletionRecords", in: context)
        cacheEntityIDs(Project.self, key: "projects", in: context)
        cacheEntityIDs(ProjectRole.self, key: "projectRoles", in: context)
        cacheEntityIDs(ProjectAssignmentTemplate.self, key: "projectAssignmentTemplates", in: context)
        cacheEntityIDs(ProjectWeekRoleAssignment.self, key: "projectWeekRoleAssignments", in: context)
        cacheEntityIDs(ProjectSession.self, key: "projectSessions", in: context)
    }

    /// Clears the lookup caches to free memory after restore is complete
    func clearIDCaches() {
        studentsByID = [:]
        lessonsByID = [:]
        topicsByID = [:]
        templateWeeksByID = [:]
        existingIDSets = [:]
    }
}
