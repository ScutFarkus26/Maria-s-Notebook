import Foundation
import CoreData
import OSLog

// MARK: - Miscellaneous Entities

extension BackupEntityImporter {

    // MARK: - Community Topics

    /// Imports community topics from DTOs.
    static func importCommunityTopics(
        _ dtos: [CommunityTopicDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDCommunityTopicEntity>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let topic = current ?? CDCommunityTopicEntity(context: viewContext)
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

    // MARK: - Community Attachments

    /// Imports community attachments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The community attachment DTOs to import
    ///   - viewContext: The model context for database operations
    ///   - existing: Looks up an already-stored an attachment by ID so it is updated in place
    ///   - topicCheck: Function to look up a community topic by ID
    static func importCommunityAttachments(
        _ dtos: [CommunityAttachmentDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDCommunityAttachment>,
        topicCheck: EntityLookup<CDCommunityTopicEntity>
    ) rethrows {
        for dto in dtos {
            let attachment = existingEntity(id: dto.id, existing: existing)
                ?? CDCommunityAttachment(context: viewContext)
            attachment.id = dto.id
            attachment.filename = dto.filename
            attachment.kind = CommunityAttachmentKind(rawValue: dto.kind) ?? .file
            // `data` is left alone: backups carry no attachment bytes, so a new
            // attachment has none and a merge keeps the ones already here (it
            // used to set them to nil).
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
        existing: ExistingLookup<CDIssue>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let i = current ?? CDIssue(context: viewContext)
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
        existing: ExistingLookup<CDIssueAction>,
        issueCheck: EntityLookup<CDIssue>
    ) rethrows {
        for dto in dtos {
            let a = existingEntity(id: dto.id, existing: existing) ?? CDIssueAction(context: viewContext)
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
        existing: ExistingLookup<CDDevelopmentSnapshotEntity>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let s = current ?? CDDevelopmentSnapshotEntity(context: viewContext)
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
        existing: ExistingLookup<CDPlanningRecommendation>
    ) rethrows {
        for dto in dtos {
            guard let lessonUUID = UUID(uuidString: dto.lessonID),
                  let sessionUUID = UUID(uuidString: dto.planningSessionID),
                  let depth = PlanningDepth(rawValue: dto.depthLevel) else { continue }
            // Decode student IDs from the blob
            let studentIDs = CloudKitStringArrayStorage.decode(from: dto.studentIDsData)
                .compactMap { UUID(uuidString: $0) }
            let rec = existingEntity(id: dto.id, existing: existing) ?? CDPlanningRecommendation(context: viewContext)
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
