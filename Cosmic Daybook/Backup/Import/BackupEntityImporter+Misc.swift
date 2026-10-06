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
    ///   - existing: Looks up an already-stored a note by ID so it is updated in place
    ///   - lessonCheck: Function to look up a lesson by ID for linking
    static func importNotes(
        _ dtos: [NoteDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDNote>
    ) rethrows {
        for dto in dtos {
            // Determine tags: prefer dto.tags, fallback to converting legacy categoryRaw if present
            let importedTags: [String]
            if let dtoTags = dto.tags, !dtoTags.isEmpty {
                importedTags = dtoTags
            } else {
                importedTags = []
            }

            let note = existingEntity(id: dto.id, existing: existing) ?? CDNote(context: viewContext)
            note.id = dto.id
            note.createdAt = dto.createdAt
            note.updatedAt = dto.updatedAt
            note.body = dto.body
            note.tags = importedTags as NSArray
            note.needsFollowUp = dto.needsFollowUp ?? false
            note.imagePath = dto.imagePath
            note.isPinned = dto.isPinned
            // A row from before the flag (v19) has none: a note already here keeps its own.
            if let include = dto.includeInReport { note.includeInReport = include }
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
    /// target type is in the store, and wires them up by id. It gets only the
    /// notes that point at something (`BackupNoteLinks`), so the notes' rows
    /// need not be kept until the end of the restore.
    /// Returns how many notes name a reminder this device doesn't have and
    /// weren't already linked to one.
    @discardableResult
    static func relinkNoteRelationships(_ notes: [BackupNoteLinks], index: BackupEntityIndex) throws -> Int {
        var missingReminder = 0
        for links in notes {
            guard let note = try index.related(CDNote.self, id: links.noteID) else { continue }
            if let id = links.workID {
                note.work = try index.related(CDWorkModel.self, id: id)
            }
            if let id = links.lessonAssignmentID {
                note.lessonAssignment = try index.related(CDLessonAssignment.self, id: id)
            }
            if let id = links.attendanceRecordID {
                // A string FK, so it restores whether or not the record itself
                // made this backup — nothing to resolve through the index.
                note.attendanceRecordID = id.uuidString
            }
            if let id = links.workCheckInID {
                note.workCheckIn = try index.related(CDWorkCheckIn.self, id: id)
            }
            if let id = links.workCompletionRecordID {
                note.workCompletionRecord = try index.related(CDWorkCompletionRecord.self, id: id)
            }
            if let id = links.studentMeetingID {
                note.studentMeeting = try index.related(CDStudentMeeting.self, id: id)
            }
            if let id = links.projectSessionID {
                note.projectSession = try index.related(CDProjectSession.self, id: id)
            }
            // Reminders aren't restored (the device's EventKit copies stay as
            // they are), so a reminder the backup names but this device lacks
            // leaves the note's link alone rather than clearing it.
            if let id = links.reminderID {
                note.reminder = try index.related(CDReminder.self, id: id) ?? note.reminder
                if note.reminder == nil { missingReminder += 1 }
            }
            if let id = links.practiceSessionID {
                note.practiceSession = try index.related(CDPracticeSession.self, id: id)
            }
            if let id = links.issueID {
                note.issue = try index.related(CDIssue.self, id: id)
            }
        }
        return missingReminder
    }

    // MARK: - CDNote Templates

    static func importNoteTemplates(
        _ dtos: [NoteTemplateDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDNoteTemplate>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let templateTags: [String]
            if let dtoTags = dto.tags, !dtoTags.isEmpty {
                templateTags = dtoTags
            } else if !dto.categoryRaw.isEmpty, dto.categoryRaw != "general" {
                templateTags = [TagHelper.tagFromNoteCategory(dto.categoryRaw)]
            } else {
                templateTags = []
            }
            let template = current ?? CDNoteTemplate(context: viewContext)
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
