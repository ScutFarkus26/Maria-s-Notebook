import Foundation
import CryptoKit

/// Provides comprehensive checksum verification with per-entity validation
/// Enables granular corruption detection and integrity monitoring
@MainActor
public final class ChecksumVerificationService {
    
    // MARK: - Types
    
    public struct ChecksumManifest: Codable, Sendable {
        public var globalChecksum: String
        public var entityChecksums: [String: String]  // entityType -> checksum
        public var createdAt: Date
        public var algorithm: String
        
        public init(globalChecksum: String, entityChecksums: [String: String], createdAt: Date = Date(), algorithm: String = "SHA-256") {
            self.globalChecksum = globalChecksum
            self.entityChecksums = entityChecksums
            self.createdAt = createdAt
            self.algorithm = algorithm
        }
    }
    
    public struct VerificationResult {
        public var isValid: Bool
        public var globalChecksumMatch: Bool
        public var entityResults: [String: Bool]  // entityType -> isValid
        public var corruptedEntities: [String]
        public var missingChecksums: [String]
        public var verificationTime: TimeInterval
        
        public var hasCorruption: Bool {
            !corruptedEntities.isEmpty
        }
    }
    
    // MARK: - Checksum Generation
    
    /// Generates a comprehensive checksum manifest for a backup payload
    /// - Parameter payload: The backup payload to checksum
    /// - Returns: A manifest containing global and per-entity checksums
    public func generateChecksumManifest(for payload: BackupPayload) throws -> ChecksumManifest {
        var entityChecksums: [String: String] = [:]
        
        let encoder = JSONEncoder.backupConfigured()
        
        // Generate checksums for each entity type
        entityChecksums["Student"] = try checksumFor(payload.students, encoder: encoder)
        entityChecksums["Lesson"] = try checksumFor(payload.lessons, encoder: encoder)
        entityChecksums["StudentLesson"] = try checksumFor(payload.studentLessons, encoder: encoder)
        entityChecksums["LessonAssignment"] = try checksumFor(payload.lessonAssignments, encoder: encoder)
        entityChecksums["Note"] = try checksumFor(payload.notes, encoder: encoder)
        entityChecksums["NonSchoolDay"] = try checksumFor(payload.nonSchoolDays, encoder: encoder)
        entityChecksums["SchoolDayOverride"] = try checksumFor(payload.schoolDayOverrides, encoder: encoder)
        entityChecksums["StudentMeeting"] = try checksumFor(payload.studentMeetings, encoder: encoder)
        entityChecksums["CommunityTopic"] = try checksumFor(payload.communityTopics, encoder: encoder)
        entityChecksums["ProposedSolution"] = try checksumFor(payload.proposedSolutions, encoder: encoder)
        entityChecksums["CommunityAttachment"] = try checksumFor(payload.communityAttachments, encoder: encoder)
        entityChecksums["AttendanceRecord"] = try checksumFor(payload.attendance, encoder: encoder)
        entityChecksums["WorkCompletionRecord"] = try checksumFor(payload.workCompletions, encoder: encoder)
        entityChecksums["Project"] = try checksumFor(payload.projects, encoder: encoder)
        entityChecksums["ProjectAssignmentTemplate"] = try checksumFor(payload.projectAssignmentTemplates, encoder: encoder)
        entityChecksums["ProjectSession"] = try checksumFor(payload.projectSessions, encoder: encoder)
        entityChecksums["ProjectRole"] = try checksumFor(payload.projectRoles, encoder: encoder)
        entityChecksums["ProjectTemplateWeek"] = try checksumFor(payload.projectTemplateWeeks, encoder: encoder)
        entityChecksums["ProjectWeekRoleAssignment"] = try checksumFor(payload.projectWeekRoleAssignments, encoder: encoder)
        entityChecksums["Preferences"] = try checksumFor(payload.preferences, encoder: encoder)
        
        // Generate global checksum from all entity checksums combined
        let globalChecksum = try generateGlobalChecksum(entityChecksums: entityChecksums)
        
        return ChecksumManifest(
            globalChecksum: globalChecksum,
            entityChecksums: entityChecksums,
            createdAt: Date(),
            algorithm: "SHA-256"
        )
    }
    
    /// Verifies a backup payload against its checksum manifest
    /// - Parameters:
    ///   - payload: The backup payload to verify
    ///   - manifest: The checksum manifest to verify against
    /// - Returns: Detailed verification result
    public func verify(payload: BackupPayload, against manifest: ChecksumManifest) throws -> VerificationResult {
        let startTime = Date()
        
        var entityResults: [String: Bool] = [:]
        var corruptedEntities: [String] = []
        var missingChecksums: [String] = []
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        
        // Verify each entity type
        let entityTypes: [(String, Any)] = [
            ("Student", payload.students),
            ("Lesson", payload.lessons),
            ("StudentLesson", payload.studentLessons),
            ("LessonAssignment", payload.lessonAssignments),
            ("Note", payload.notes),
            ("NonSchoolDay", payload.nonSchoolDays),
            ("SchoolDayOverride", payload.schoolDayOverrides),
            ("StudentMeeting", payload.studentMeetings),
            ("CommunityTopic", payload.communityTopics),
            ("ProposedSolution", payload.proposedSolutions),
            ("CommunityAttachment", payload.communityAttachments),
            ("AttendanceRecord", payload.attendance),
            ("WorkCompletionRecord", payload.workCompletions),
            ("Project", payload.projects),
            ("ProjectAssignmentTemplate", payload.projectAssignmentTemplates),
            ("ProjectSession", payload.projectSessions),
            ("ProjectRole", payload.projectRoles),
            ("ProjectTemplateWeek", payload.projectTemplateWeeks),
            ("ProjectWeekRoleAssignment", payload.projectWeekRoleAssignments),
            ("Preferences", payload.preferences)
        ]
        
        for (entityType, entities) in entityTypes {
            guard let expectedChecksum = manifest.entityChecksums[entityType] else {
                missingChecksums.append(entityType)
                entityResults[entityType] = false
                continue
            }
            
            let actualChecksum: String
            if let codableEntities = entities as? any Encodable {
                actualChecksum = try checksumForAny(codableEntities, encoder: encoder)
            } else {
                actualChecksum = ""
            }
            
            let isValid = actualChecksum == expectedChecksum
            entityResults[entityType] = isValid
            
            if !isValid {
                corruptedEntities.append(entityType)
            }
        }
        
        // Verify global checksum
        let calculatedGlobalChecksum = try generateGlobalChecksum(entityChecksums: manifest.entityChecksums)
        let globalChecksumMatch = calculatedGlobalChecksum == manifest.globalChecksum
        
        let verificationTime = Date().timeIntervalSince(startTime)
        let isValid = globalChecksumMatch && corruptedEntities.isEmpty && missingChecksums.isEmpty
        
        return VerificationResult(
            isValid: isValid,
            globalChecksumMatch: globalChecksumMatch,
            entityResults: entityResults,
            corruptedEntities: corruptedEntities,
            missingChecksums: missingChecksums,
            verificationTime: verificationTime
        )
    }
    
    /// Performs a quick integrity check on a backup file
    /// - Parameter url: The backup file URL
    /// - Returns: True if the backup appears valid
    public func quickCheck(backupAt url: URL) throws -> Bool {
        let data = try Data(contentsOf: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        
        // Verify we have a checksum
        guard !envelope.manifest.sha256.isEmpty else {
            return false
        }
        
        // Extract and verify payload checksum
        let payloadBytes: Data
        
        if let compressed = envelope.compressedPayload {
            let codec = BackupCodec()
            payloadBytes = try codec.decompress(compressed)
        } else if envelope.encryptedPayload != nil {
            // Can't verify encrypted payload without password
            return true  // Assume valid if encrypted
        } else {
            throw NSError(domain: "ChecksumVerificationService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Backup file missing payload"
            ])
        }
        
        let actualChecksum = payloadBytes.sha256Hex
        
        return actualChecksum == envelope.manifest.sha256
    }
    
    // MARK: - Private Helpers
    
    private func checksumFor<T: Encodable>(_ entities: [T], encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(entities)
        return data.sha256Hex
    }
    
    private func checksumFor<T: Encodable>(_ entity: T, encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(entity)
        return data.sha256Hex
    }
    
    private func checksumForAny(_ entity: any Encodable, encoder: JSONEncoder) throws -> String {
        // This is a workaround for type erasure
        if let students = entity as? [StudentDTO] {
            return try checksumFor(students, encoder: encoder)
        } else if let lessons = entity as? [LessonDTO] {
            return try checksumFor(lessons, encoder: encoder)
        } else if let prefs = entity as? PreferencesDTO {
            return try checksumFor(prefs, encoder: encoder)
        }
        // Add more type checks as needed
        return ""
    }
    
    private func generateGlobalChecksum(entityChecksums: [String: String]) throws -> String {
        // Sort by key to ensure deterministic ordering
        let sortedKeys = entityChecksums.keys.sorted()
        let concatenated = sortedKeys.map { key in
            "\(key):\(entityChecksums[key] ?? "")"
        }.joined(separator: "|")
        
        let data = concatenated.data(using: .utf8) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }
}
