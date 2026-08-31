import Foundation
import CoreData
import OSLog

// MARK: - Miscellaneous Entities

extension BackupEntityImporter {

    // MARK: - Notes

    /// Imports notes from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The note DTOs to import
    ///   - viewContext: The model context for database operations
    ///   - existingCheck: Function to check if a note already exists
    ///   - lessonCheck: Function to look up a lesson by ID for linking
    static func importNotes(
        _ dtos: [NoteDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) { continue }
            } catch {
                Logger.backup.warning("Failed to check existing note: \(error.localizedDescription, privacy: .public)")
                continue
            }

            // Determine tags: prefer dto.tags, fallback to converting legacy categoryRaw if present
            let importedTags: [String]
            if let dtoTags = dto.tags, !dtoTags.isEmpty {
                importedTags = dtoTags
            } else {
                importedTags = []
            }

            let note = CDNote(context: viewContext)
            note.id = dto.id
            note.createdAt = dto.createdAt
            note.updatedAt = dto.updatedAt
            note.body = dto.body
            note.tags = importedTags as NSArray
            note.needsFollowUp = dto.needsFollowUp ?? false
            note.imagePath = dto.imagePath
            note.isPinned = dto.isPinned
            note.includeInReport = dto.includeInReport ?? false
            note.reportedBy = dto.reportedBy
            note.reporterName = dto.reporterName
            note.communityTopicID = dto.communityTopicID
            note.schoolDayOverrideID = dto.schoolDayOverrideID
            note.studentTrackEnrollmentID = dto.studentTrackEnrollmentID
            note.goingOutID = dto.goingOutID

            if let data = dto.scope.data(using: .utf8) {
                do {
                    let scope = try JSONDecoder().decode(NoteScope.self, from: data)
                    note.scope = scope
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to decode note scope: \(desc, privacy: .public)")
                }
            }

            // note → lesson is a cross-store string FK, not a Core Data relationship.
            // Restore the raw ID unconditionally: requiring the lesson to already be
            // resolvable here silently dropped the link (the computed `lesson`
            // accessor tolerates a dangling ID and resolves lazily).
            note.lessonID = dto.lessonID?.uuidString

            viewContext.insert(note)
        }
    }

    /// Relinks a note's context relationships after all entities are imported.
    ///
    /// Notes import early, but most of their relationship targets (work,
    /// check-ins, meetings, issues, etc.) import in later phases — so they can't
    /// be resolved at note-import time. This runs as a final pass, once every
    /// target type is in the store, and wires them up by id.
    @MainActor
    static func relinkNoteRelationships(_ dtos: [NoteDTO], index: BackupEntityIndex) throws {
        for dto in dtos {
            guard let note = try index.related(CDNote.self, id: dto.id) else { continue }
            if let id = dto.workID {
                note.work = try index.related(CDWorkModel.self, id: id)
            }
            if let id = dto.lessonAssignmentID {
                note.lessonAssignment = try index.related(CDLessonAssignment.self, id: id)
            }
            if let id = dto.attendanceRecordID {
                // A string FK, so it restores whether or not the record itself
                // made this backup — nothing to resolve through the index.
                note.attendanceRecordID = id.uuidString
            }
            if let id = dto.workCheckInID {
                note.workCheckIn = try index.related(CDWorkCheckIn.self, id: id)
            }
            if let id = dto.workCompletionRecordID {
                note.workCompletionRecord = try index.related(CDWorkCompletionRecord.self, id: id)
            }
            if let id = dto.studentMeetingID {
                note.studentMeeting = try index.related(CDStudentMeeting.self, id: id)
            }
            if let id = dto.projectSessionID {
                note.projectSession = try index.related(CDProjectSession.self, id: id)
            }
            if let id = dto.reminderID {
                note.reminder = try index.related(CDReminder.self, id: id)
            }
            if let id = dto.practiceSessionID {
                note.practiceSession = try index.related(CDPracticeSession.self, id: id)
            }
            if let id = dto.issueID {
                note.issue = try index.related(CDIssue.self, id: id)
            }
        }
    }

    // MARK: - CDNote Templates

    static func importNoteTemplates(
        _ dtos: [NoteTemplateDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let templateTags: [String]
            if let dtoTags = dto.tags, !dtoTags.isEmpty {
                templateTags = dtoTags
            } else if !dto.categoryRaw.isEmpty, dto.categoryRaw != "general" {
                templateTags = [TagHelper.tagFromNoteCategory(dto.categoryRaw)]
            } else {
                templateTags = []
            }
            let template = CDNoteTemplate(context: viewContext)
            template.id = dto.id
            template.createdAt = dto.createdAt
            template.title = dto.title
            template.body = dto.body
            template.tags = templateTags as NSArray
            template.sortOrder = Int64(dto.sortOrder)
            template.isBuiltIn = dto.isBuiltIn
            return template
        })
    }

    // MARK: - Community Topics

    /// Imports community topics from DTOs.
    static func importCommunityTopics(
        _ dtos: [CommunityTopicDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let topic = CDCommunityTopicEntity(context: viewContext)
            topic.id = dto.id
            topic.title = dto.title
            topic.issueDescription = dto.issueDescription
            topic.createdAt = dto.createdAt
            topic.addressedDate = dto.addressedDate
            topic.resolution = dto.resolution
            topic.raisedBy = dto.raisedBy
            topic.tags = dto.tags
            return topic
        })
    }

    // MARK: - Proposed Solutions

    /// Imports proposed solutions from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The proposed solution DTOs to import
    ///   - viewContext: The model context for database operations
    ///   - existingCheck: Function to check if a solution already exists
    ///   - topicCheck: Function to look up a community topic by ID
    static func importProposedSolutions(
        _ dtos: [ProposedSolutionDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck,
        topicCheck: EntityLookup<CDCommunityTopicEntity>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) { continue }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check existing proposed solution: \(desc, privacy: .public)")
                continue
            }

            let solution = CDProposedSolutionEntity(context: viewContext)
            solution.id = dto.id
            solution.title = dto.title
            solution.details = dto.details
            solution.proposedBy = dto.proposedBy
            solution.createdAt = dto.createdAt
            solution.isAdopted = dto.isAdopted

            if let topicID = dto.topicID {
                do {
                    if let topic = try topicCheck(topicID) {
                        solution.topic = topic
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check topic for proposed solution: \(desc, privacy: .public)")
                }
            }

            viewContext.insert(solution)
        }
    }

    // MARK: - Community Attachments

    /// Imports community attachments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The community attachment DTOs to import
    ///   - viewContext: The model context for database operations
    ///   - existingCheck: Function to check if an attachment already exists
    ///   - topicCheck: Function to look up a community topic by ID
    static func importCommunityAttachments(
        _ dtos: [CommunityAttachmentDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck,
        topicCheck: EntityLookup<CDCommunityTopicEntity>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) { continue }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check existing community attachment: \(desc, privacy: .public)")
                continue
            }

            let attachment = CDCommunityAttachmentEntity(context: viewContext)
            attachment.id = dto.id
            attachment.filename = dto.filename
            attachment.kind = CommunityAttachmentKind(rawValue: dto.kind) ?? .file
            attachment.data = nil
            attachment.createdAt = dto.createdAt

            if let topicID = dto.topicID {
                do {
                    if let topic = try topicCheck(topicID) {
                        attachment.topic = topic
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check topic for community attachment: \(desc, privacy: .public)")
                }
            }

            viewContext.insert(attachment)
        }
    }

    // MARK: - Issues

    static func importIssues(
        _ dtos: [IssueDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let i = CDIssue(context: viewContext)
            i.id = dto.id
            i.title = dto.title
            i.issueDescription = dto.issueDescription
            i.categoryRaw = (IssueCategory(rawValue: dto.categoryRaw) ?? .other).rawValue
            i.priorityRaw = (IssuePriority(rawValue: dto.priorityRaw) ?? .medium).rawValue
            i.statusRaw = (IssueStatus(rawValue: dto.statusRaw) ?? .open).rawValue
            i.studentIDs = dto.studentIDs
            i.location = dto.location
            i.createdAt = dto.createdAt
            i.updatedAt = dto.updatedAt
            i.modifiedAt = dto.modifiedAt
            i.resolvedAt = dto.resolvedAt
            i.resolutionSummary = dto.resolutionSummary
            return i
        })
    }

    // MARK: - CDIssue Actions

    static func importIssueActions(
        _ dtos: [IssueActionDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck,
        issueCheck: EntityLookup<CDIssue>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let a = CDIssueAction(context: viewContext)
            a.id = dto.id
            a.actionTypeRaw = (IssueActionType(rawValue: dto.actionTypeRaw) ?? .note).rawValue
            a.actionDescription = dto.actionDescription
            a.actionDate = dto.actionDate
            a.participantStudentIDs = dto.participantStudentIDs
            a.nextSteps = dto.nextSteps
            a.followUpRequired = dto.followUpRequired
            a.followUpDate = dto.followUpDate
            a.createdAt = dto.createdAt
            a.updatedAt = dto.updatedAt
            a.modifiedAt = dto.modifiedAt
            a.issueID = dto.issueID
            a.followUpCompleted = dto.followUpCompleted
            if let issueUUID = UUID(uuidString: dto.issueID) {
                do {
                    if let issue = try issueCheck(issueUUID) {
                        a.issue = issue
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check issue for action: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(a)
        }
    }

    // MARK: - Development Snapshots

    static func importDevelopmentSnapshots(
        _ dtos: [DevelopmentSnapshotDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let s = CDDevelopmentSnapshotEntity(context: viewContext)
            s.id = dto.id
            s.studentID = dto.studentID
            s.generatedAt = dto.generatedAt
            s.lookbackDays = Int64(dto.lookbackDays)
            s.analysisVersion = dto.analysisVersion
            s.overallProgress = dto.overallProgress
            s.keyStrengths = dto.keyStrengths
            s.areasForGrowth = dto.areasForGrowth
            s.developmentalMilestones = dto.developmentalMilestones
            s.observedPatterns = dto.observedPatterns
            s.behavioralTrends = dto.behavioralTrends
            s.socialEmotionalInsights = dto.socialEmotionalInsights
            s.recommendedNextLessons = dto.recommendedNextLessons
            s.suggestedPracticeFocus = dto.suggestedPracticeFocus
            s.interventionSuggestions = dto.interventionSuggestions
            s.totalNotesAnalyzed = Int64(dto.totalNotesAnalyzed)
            s.practiceSessionsAnalyzed = Int64(dto.practiceSessionsAnalyzed)
            s.workCompletionsAnalyzed = Int64(dto.workCompletionsAnalyzed)
            s.averagePracticeQuality = dto.averagePracticeQuality ?? 0
            s.independenceLevel = dto.independenceLevel ?? 0
            s.rawAnalysisJSON = dto.rawAnalysisJSON
            s.userNotes = dto.userNotes
            s.isReviewed = dto.isReviewed
            s.sharedWithParents = dto.sharedWithParents
            s.sharedAt = dto.sharedAt
            return s
        })
    }

    // MARK: - CDPlanningRecommendation

    static func importPlanningRecommendations(
        _ dtos: [PlanningRecommendationDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let lessonUUID = UUID(uuidString: dto.lessonID),
                  let sessionUUID = UUID(uuidString: dto.planningSessionID),
                  let depth = PlanningDepth(rawValue: dto.depthLevel) else { continue }
            // Decode student IDs from the blob
            let studentIDs = CloudKitStringArrayStorage.decode(from: dto.studentIDsData)
                .compactMap { UUID(uuidString: $0) }
            let rec = CDPlanningRecommendation(context: viewContext)
            rec.id = dto.id
            rec.lessonID = lessonUUID.uuidString
            rec.studentIDs = studentIDs.map(\.uuidString)
            rec.reasoning = dto.reasoning
            rec.confidence = dto.confidence
            rec.priority = Int64(dto.priority)
            rec.subjectContext = dto.subjectContext
            rec.groupContext = dto.groupContext
            rec.planningSessionID = sessionUUID.uuidString
            rec.depthLevel = depth.rawValue
            rec.createdAt = dto.createdAt
            rec.modifiedAt = dto.modifiedAt
            rec.decisionRaw = dto.decisionRaw
            rec.decisionAt = dto.decisionAt
            rec.teacherNote = dto.teacherNote
            rec.outcomeRaw = dto.outcomeRaw
            rec.outcomeRecordedAt = dto.outcomeRecordedAt
            rec.presentationID = dto.presentationID
            viewContext.insert(rec)
        }
    }

}
