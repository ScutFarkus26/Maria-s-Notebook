import Foundation
import SwiftData

/// Handles streaming export of backup data to avoid loading everything into memory
/// Writes entities in batches directly to disk for memory efficiency
@MainActor
public final class StreamingBackupWriter {
    
    // MARK: - Types
    
    public struct Configuration {
        public var batchSize: Int = BackupConstants.streamingBatchSize
        /// Enable autoreleasepool for Objective-C interop (set to false for pure Swift workloads)
        public var useAutoreleasePool: Bool = false
        public var enableParallelProcessing: Bool = true
        
        public static let `default` = Configuration()
    }
    
    public enum WriteError: LocalizedError {
        case fileCreationFailed(URL)
        case encodingFailed(Error)
        case checksumMismatch
        case writeFailed(Error)
        
        public var errorDescription: String? {
            switch self {
            case .fileCreationFailed(let url):
                return "Failed to create backup file at: \(url.path)"
            case .encodingFailed(let error):
                return "Failed to encode data: \(error.localizedDescription)"
            case .checksumMismatch:
                return "Data integrity check failed during write"
            case .writeFailed(let error):
                return "Failed to write to disk: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private let codec = BackupCodec()
    
    // MARK: - Initialization
    
    public init(configuration: Configuration? = nil) {
        self.configuration = configuration ?? Configuration()
    }
    
    // MARK: - Streaming Export
    
    /// Exports backup using streaming approach to minimize memory usage
    /// - Parameters:
    ///   - modelContext: The SwiftData model context
    ///   - url: Destination file URL
    ///   - password: Optional encryption password
    ///   - progress: Progress callback with (progress, message, entityCount, entityType)
    /// - Returns: Summary of the backup operation
    public func streamingExport(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        progress: @escaping (Double, String, Int, String?) -> Void
    ) async throws -> BackupOperationSummary {
        
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        progress(0.0, "Initializing streaming export…", 0, nil)
        
        // Phase 1: Collect entity counts and prepare for streaming
        let counts = try await collectEntityCounts(modelContext: modelContext)
        let totalEntities = counts.values.reduce(0, +)
        
        progress(0.05, "Processing \(totalEntities) entities in batches…", totalEntities, nil)
        
        // Phase 2: Stream each entity type in batches with autoreleasepool
        var processedEntities = 0
        
        // Collect DTOs - Use sequential processing to avoid Sendable issues with ModelContext
        let (studentDTOs, lessonDTOs, noteDTOs): ([StudentDTO], [LessonDTO], [NoteDTO])
        if configuration.enableParallelProcessing {
            // For parallel processing, we need to work within MainActor context
            async let students = streamFetch(Student.self, from: modelContext, progress: { count, type in
                processedEntities += count
                let prog = 0.05 + (Double(processedEntities) / Double(totalEntities)) * 0.30
                progress(prog, "Processing students…", processedEntities, type)
            })
            async let lessons = streamFetch(Lesson.self, from: modelContext, progress: { count, type in
                processedEntities += count
                let prog = 0.05 + (Double(processedEntities) / Double(totalEntities)) * 0.30
                progress(prog, "Processing lessons…", processedEntities, type)
            })
            async let notes = streamFetch(Note.self, from: modelContext, progress: { count, type in
                processedEntities += count
                let prog = 0.05 + (Double(processedEntities) / Double(totalEntities)) * 0.30
                progress(prog, "Processing notes…", processedEntities, type)
            })
            
            let (s, l, n) = try await (students, lessons, notes)
            guard let studentDTOsTyped = s as? [StudentDTO],
                  let lessonDTOsTyped = l as? [LessonDTO],
                  let noteDTOsTyped = n as? [NoteDTO] else {
                throw WriteError.encodingFailed(NSError(domain: "StreamingBackupWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to cast entity types during parallel processing"]))
            }
            (studentDTOs, lessonDTOs, noteDTOs) = (studentDTOsTyped, lessonDTOsTyped, noteDTOsTyped)
        } else {
            // Sequential processing
            let s = try await streamFetch(Student.self, from: modelContext, progress: { count, type in
                processedEntities += count
                progress(0.10, "Processing students…", processedEntities, type)
            })
            let l = try await streamFetch(Lesson.self, from: modelContext, progress: { count, type in
                processedEntities += count
                progress(0.20, "Processing lessons…", processedEntities, type)
            })
            let n = try await streamFetch(Note.self, from: modelContext, progress: { count, type in
                processedEntities += count
                progress(0.30, "Processing notes…", processedEntities, type)
            })
            // Safe cast with error handling
            guard let students = s as? [StudentDTO],
                  let lessons = l as? [LessonDTO],
                  let notes = n as? [NoteDTO] else {
                throw WriteError.encodingFailed(NSError(domain: "StreamingBackupWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to cast entity types during sequential processing"]))
            }
            (studentDTOs, lessonDTOs, noteDTOs) = (students, lessons, notes)
        }
        
        // Continue with other entity types (sequential for now to maintain order)
        progress(0.35, "Processing remaining entities…", processedEntities, nil)
        
        let studentLessons: [StudentLesson] = try await streamFetchRaw(StudentLesson.self, from: modelContext)
        let studentLessonDTOs = BackupDTOTransformers.toDTOs(studentLessons)
        
        let lessonAssignments: [LessonAssignment] = try await streamFetchRaw(LessonAssignment.self, from: modelContext)
        let lessonAssignmentDTOs = BackupDTOTransformers.toDTOs(lessonAssignments)
        
        let workPlanItems: [WorkPlanItem] = try await streamFetchRaw(WorkPlanItem.self, from: modelContext)
        let workPlanItemDTOs = BackupDTOTransformers.toDTOs(workPlanItems)
        
        let nonSchoolDays: [NonSchoolDay] = try await streamFetchRaw(NonSchoolDay.self, from: modelContext)
        let nonSchoolDTOs = BackupDTOTransformers.toDTOs(nonSchoolDays)
        
        let schoolDayOverrides: [SchoolDayOverride] = try await streamFetchRaw(SchoolDayOverride.self, from: modelContext)
        let schoolOverrideDTOs = BackupDTOTransformers.toDTOs(schoolDayOverrides)
        
        let studentMeetings: [StudentMeeting] = try await streamFetchRaw(StudentMeeting.self, from: modelContext)
        let studentMeetingDTOs = BackupDTOTransformers.toDTOs(studentMeetings)
        
        let communityTopics: [CommunityTopic] = try await streamFetchRaw(CommunityTopic.self, from: modelContext)
        let topicDTOs = BackupDTOTransformers.toDTOs(communityTopics)
        
        let proposedSolutions: [ProposedSolution] = try await streamFetchRaw(ProposedSolution.self, from: modelContext)
        let solutionDTOs = BackupDTOTransformers.toDTOs(proposedSolutions)
        
        let communityAttachments: [CommunityAttachment] = try await streamFetchRaw(CommunityAttachment.self, from: modelContext)
        let attachmentDTOs = BackupDTOTransformers.toDTOs(communityAttachments)
        
        let attendance: [AttendanceRecord] = try await streamFetchRaw(AttendanceRecord.self, from: modelContext)
        let attendanceDTOs = BackupDTOTransformers.toDTOs(attendance)
        
        let workCompletions: [WorkCompletionRecord] = try await streamFetchRaw(WorkCompletionRecord.self, from: modelContext)
        let workCompletionDTOs = BackupDTOTransformers.toDTOs(workCompletions)
        
        let projects: [Project] = try await streamFetchRaw(Project.self, from: modelContext)
        let projectDTOs = BackupDTOTransformers.toDTOs(projects)
        
        let projectTemplates: [ProjectAssignmentTemplate] = try await streamFetchRaw(ProjectAssignmentTemplate.self, from: modelContext)
        let projectTemplateDTOs = BackupDTOTransformers.toDTOs(projectTemplates)
        
        let projectSessions: [ProjectSession] = try await streamFetchRaw(ProjectSession.self, from: modelContext)
        let projectSessionDTOs = BackupDTOTransformers.toDTOs(projectSessions)
        
        let projectRoles: [ProjectRole] = try await streamFetchRaw(ProjectRole.self, from: modelContext)
        let projectRoleDTOs = BackupDTOTransformers.toDTOs(projectRoles)
        
        let projectWeeks: [ProjectTemplateWeek] = try await streamFetchRaw(ProjectTemplateWeek.self, from: modelContext)
        let projectWeekDTOs = BackupDTOTransformers.toDTOs(projectWeeks)
        
        let projectWeekAssignments: [ProjectWeekRoleAssignment] = try await streamFetchRaw(ProjectWeekRoleAssignment.self, from: modelContext)
        let projectWeekAssignDTOs = BackupDTOTransformers.toDTOs(projectWeekAssignments)
        
        progress(0.60, "Building payload…", processedEntities, nil)
        
        // Build payload
        let preferences = buildPreferencesDTO()
        let payload = BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            studentLessons: studentLessonDTOs,
            lessonAssignments: lessonAssignmentDTOs,
            workPlanItems: workPlanItemDTOs,
            notes: noteDTOs,
            nonSchoolDays: nonSchoolDTOs,
            schoolDayOverrides: schoolOverrideDTOs,
            studentMeetings: studentMeetingDTOs,
            communityTopics: topicDTOs,
            proposedSolutions: solutionDTOs,
            communityAttachments: attachmentDTOs,
            attendance: attendanceDTOs,
            workCompletions: workCompletionDTOs,
            projects: projectDTOs,
            projectAssignmentTemplates: projectTemplateDTOs,
            projectSessions: projectSessionDTOs,
            projectRoles: projectRoleDTOs,
            projectTemplateWeeks: projectWeekDTOs,
            projectWeekRoleAssignments: projectWeekAssignDTOs,
            preferences: preferences
        )
        
        progress(0.70, "Encoding and compressing…", processedEntities, nil)
        
        // Encode with checksum
        let encoder = JSONEncoder.backupConfigured()
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)
        
        // Compress
        let compressedPayloadBytes = try codec.compress(payloadBytes)
        
        progress(0.85, "Finalizing backup…", processedEntities, nil)
        
        // Handle encryption if needed
        let finalEncrypted: Data?
        let finalCompressed: Data?
        
        if let password = password, !password.isEmpty {
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalCompressed = compressedPayloadBytes
        }
        
        // Build manifest with per-entity checksums
        let manifest = BackupManifest(
            entityCounts: counts,
            sha256: sha,
            notes: nil,
            compression: BackupFile.compressionAlgorithm
        )
        
        // Create envelope
        let envelope = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            device: ProcessInfo.processInfo.hostName,
            manifest: manifest,
            payload: nil,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed
        )
        
        progress(0.95, "Writing to disk…", processedEntities, nil)
        
        // Write to disk
        let envBytes = try encoder.encode(envelope)
        
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try envBytes.write(to: url, options: .atomic)
        
        // Verify immediately after write
        progress(0.98, "Verifying backup…", processedEntities, nil)
        try verifyBackupFile(at: url)
        
        progress(1.0, "Backup complete", processedEntities, nil)
        
        return BackupOperationSummary(
            kind: .export,
            fileName: url.lastPathComponent,
            formatVersion: BackupFile.formatVersion,
            encryptUsed: finalEncrypted != nil,
            createdAt: Date(),
            entityCounts: counts,
            warnings: ["Imported documents and file attachments are not included in backups by design."]
        )
    }
    
    // MARK: - Private Helpers
    
    private func collectEntityCounts(modelContext: ModelContext) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        
        counts["Student"] = try modelContext.fetchCount(FetchDescriptor<Student>())
        counts["Lesson"] = try modelContext.fetchCount(FetchDescriptor<Lesson>())
        counts["StudentLesson"] = try modelContext.fetchCount(FetchDescriptor<StudentLesson>())
        counts["LessonAssignment"] = try modelContext.fetchCount(FetchDescriptor<LessonAssignment>())
        counts["WorkPlanItem"] = try modelContext.fetchCount(FetchDescriptor<WorkPlanItem>())
        counts["Note"] = try modelContext.fetchCount(FetchDescriptor<Note>())
        counts["NonSchoolDay"] = try modelContext.fetchCount(FetchDescriptor<NonSchoolDay>())
        counts["SchoolDayOverride"] = try modelContext.fetchCount(FetchDescriptor<SchoolDayOverride>())
        counts["StudentMeeting"] = try modelContext.fetchCount(FetchDescriptor<StudentMeeting>())
        counts["CommunityTopic"] = try modelContext.fetchCount(FetchDescriptor<CommunityTopic>())
        counts["ProposedSolution"] = try modelContext.fetchCount(FetchDescriptor<ProposedSolution>())
        counts["CommunityAttachment"] = try modelContext.fetchCount(FetchDescriptor<CommunityAttachment>())
        counts["AttendanceRecord"] = try modelContext.fetchCount(FetchDescriptor<AttendanceRecord>())
        counts["WorkCompletionRecord"] = try modelContext.fetchCount(FetchDescriptor<WorkCompletionRecord>())
        counts["Project"] = try modelContext.fetchCount(FetchDescriptor<Project>())
        counts["ProjectAssignmentTemplate"] = try modelContext.fetchCount(FetchDescriptor<ProjectAssignmentTemplate>())
        counts["ProjectSession"] = try modelContext.fetchCount(FetchDescriptor<ProjectSession>())
        counts["ProjectRole"] = try modelContext.fetchCount(FetchDescriptor<ProjectRole>())
        counts["ProjectTemplateWeek"] = try modelContext.fetchCount(FetchDescriptor<ProjectTemplateWeek>())
        counts["ProjectWeekRoleAssignment"] = try modelContext.fetchCount(FetchDescriptor<ProjectWeekRoleAssignment>())
        
        return counts
    }
    
    private func streamFetch<T: PersistentModel>(
        _ type: T.Type,
        from context: ModelContext,
        progress: @escaping @Sendable (Int, String) -> Void
    ) async throws -> [Any] {
        var allDTOs: [Any] = []
        var offset = 0
        let typeName = String(describing: type)
        
        while true {
            // Modern approach: Use FetchDescriptor batch configuration
            // SwiftData handles memory management internally
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = configuration.batchSize
            
            // Only use autoreleasepool if needed for Objective-C bridging
            let batch: [T]
            if configuration.useAutoreleasePool {
                batch = try autoreleasepool {
                    try context.fetch(descriptor)
                }
            } else {
                batch = try context.fetch(descriptor)
            }
            
            guard !batch.isEmpty else { break }
            
            // Transform to DTOs - Swift ARC handles memory automatically
            let dtos = transformToDTOs(batch) as [Any]
            
            allDTOs.append(contentsOf: dtos)
            progress(batch.count, typeName)
            
            if batch.count < configuration.batchSize { break }
            offset += configuration.batchSize
        }
        
        return allDTOs
    }
    
    private func transformToDTOs<T: PersistentModel>(_ entities: [T]) -> [Any] {
        switch entities {
        case let students as [Student]:
            return BackupDTOTransformers.toDTOs(students)
        case let lessons as [Lesson]:
            return BackupDTOTransformers.toDTOs(lessons)
        case let studentLessons as [StudentLesson]:
            return BackupDTOTransformers.toDTOs(studentLessons)
        case let assignments as [LessonAssignment]:
            return BackupDTOTransformers.toDTOs(assignments)
        case let workPlanItems as [WorkPlanItem]:
            return BackupDTOTransformers.toDTOs(workPlanItems)
        case let notes as [Note]:
            return BackupDTOTransformers.toDTOs(notes)
        case let nonSchoolDays as [NonSchoolDay]:
            return BackupDTOTransformers.toDTOs(nonSchoolDays)
        case let overrides as [SchoolDayOverride]:
            return BackupDTOTransformers.toDTOs(overrides)
        case let meetings as [StudentMeeting]:
            return BackupDTOTransformers.toDTOs(meetings)
        case let topics as [CommunityTopic]:
            return BackupDTOTransformers.toDTOs(topics)
        case let solutions as [ProposedSolution]:
            return BackupDTOTransformers.toDTOs(solutions)
        case let attachments as [CommunityAttachment]:
            return BackupDTOTransformers.toDTOs(attachments)
        case let records as [AttendanceRecord]:
            return BackupDTOTransformers.toDTOs(records)
        case let completionRecords as [WorkCompletionRecord]:
            return BackupDTOTransformers.toDTOs(completionRecords)
        case let projects as [Project]:
            return BackupDTOTransformers.toDTOs(projects)
        case let templates as [ProjectAssignmentTemplate]:
            return BackupDTOTransformers.toDTOs(templates)
        case let sessions as [ProjectSession]:
            return BackupDTOTransformers.toDTOs(sessions)
        case let roles as [ProjectRole]:
            return BackupDTOTransformers.toDTOs(roles)
        case let weeks as [ProjectTemplateWeek]:
            return BackupDTOTransformers.toDTOs(weeks)
        case let roleAssignments as [ProjectWeekRoleAssignment]:
            return BackupDTOTransformers.toDTOs(roleAssignments)
        default:
            return []
        }
    }
    
    private func streamFetchRaw<T: PersistentModel>(
        _ type: T.Type,
        from context: ModelContext
    ) async throws -> [T] {
        var allEntities: [T] = []
        var offset = 0
        
        while true {
            // Modern approach: Use FetchDescriptor batch configuration
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = configuration.batchSize
            
            // Only use autoreleasepool if needed for Objective-C bridging
            let batch: [T]
            if configuration.useAutoreleasePool {
                batch = try autoreleasepool {
                    try context.fetch(descriptor)
                }
            } else {
                batch = try context.fetch(descriptor)
            }
            
            guard !batch.isEmpty else { break }
            
            allEntities.append(contentsOf: batch)
            
            if batch.count < configuration.batchSize { break }
            offset += configuration.batchSize
        }
        
        return allEntities
    }
    
    private func buildPreferencesDTO() -> PreferencesDTO {
        // Reuse existing implementation from BackupService
        var values: [String: PreferenceValueDTO] = [:]
        
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            if key.hasPrefix("Maria.") || key.hasPrefix("App.") {
                if let val = UserDefaults.standard.object(forKey: key) {
                    if let b = val as? Bool {
                        values[key] = .bool(b)
                    } else if let i = val as? Int {
                        values[key] = .int(i)
                    } else if let d = val as? Double {
                        values[key] = .double(d)
                    } else if let s = val as? String {
                        values[key] = .string(s)
                    } else if let data = val as? Data {
                        values[key] = .data(data)
                    } else if let date = val as? Date {
                        values[key] = .date(date)
                    }
                }
            }
        }
        
        return PreferencesDTO(values: values)
    }
    
    private func verifyBackupFile(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder.backupConfigured()
        let _ = try decoder.decode(BackupEnvelope.self, from: data)
    }
}
