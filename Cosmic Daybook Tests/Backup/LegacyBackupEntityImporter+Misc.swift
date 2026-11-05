// swiftlint:disable file_length
import CoreData
import Foundation
import OSLog
@testable import CosmicDaybook

// More of the old restores (`LegacyBackupEntityImporter.swift`): a906650c0's
// `Backup/Import/BackupEntityImporter+Misc.swift` (with the end-of-restore note
// relink), `Backup/Import/BackupNoteLinks.swift` (as `LegacyBackupNoteLinks`),
// `+Todo` and `+Tracks`, copied verbatim; only the names are changed. Do not
// "fix" or modernise this code: its only job is to be the old code.

// MARK: - Backup/Import/BackupEntityImporter+Misc.swift

// MARK: - Miscellaneous Entities

extension LegacyBackupEntityImporter {

    // MARK: - Notes

    /// Imports notes from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The note DTOs to import
    ///   - viewContext: The model context for database operations
    ///   - existing: Looks up an already-stored a note by ID so it is updated in place
    ///   - lessonCheck: Function to look up a lesson by ID for linking
    static func importNotes(
        _ dtos: [LegacyNoteDTO],
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
    /// notes that point at something (`LegacyBackupNoteLinks`), so the notes' rows
    /// need not be kept until the end of the restore. A note's link to an
    /// Apple Reminders copy (retired) is left as it is on this device.
    static func relinkNoteRelationships(_ notes: [LegacyBackupNoteLinks], index: BackupEntityIndex) throws {
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
            if let id = links.issueID {
                note.issue = try index.related(CDIssue.self, id: id)
            }
        }
    }

    // MARK: - Community Topics

    /// Imports community topics from DTOs.
    static func importCommunityTopics(
        _ dtos: [LegacyCommunityTopicDTO],
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
        _ dtos: [LegacyCommunityAttachmentDTO],
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
        _ dtos: [LegacyIssueDTO],
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
        _ dtos: [LegacyIssueActionDTO],
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
        _ dtos: [LegacyDevelopmentSnapshotDTO],
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
        _ dtos: [LegacyPlanningRecommendationDTO],
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

// MARK: - Backup/Import/BackupNoteLinks.swift

// What the end-of-restore note relink needs from a restored note.

/// A restored note's id and the ids of the records it points at. Notes import
/// early and most of their targets later, so the restore keeps these — not the
/// notes' rows — until every target type is in, then relinks
/// (`LegacyBackupEntityImporter.relinkNoteRelationships`).
nonisolated struct LegacyBackupNoteLinks: Sendable {
    let noteID: UUID
    let workID: UUID?
    let lessonAssignmentID: UUID?
    let attendanceRecordID: UUID?
    let workCheckInID: UUID?
    let workCompletionRecordID: UUID?
    let studentMeetingID: UUID?
    let projectSessionID: UUID?
    let issueID: UUID?

    /// Nil for a note that points at nothing the relink sets; relinking it
    /// would only look the note up.
    init?(_ note: LegacyNoteDTO) {
        let targets: [UUID?] = [
            note.workID, note.lessonAssignmentID, note.attendanceRecordID, note.workCheckInID,
            note.workCompletionRecordID, note.studentMeetingID, note.projectSessionID,
            note.issueID
        ]
        guard targets.contains(where: { $0 != nil }) else { return nil }
        noteID = note.id
        workID = note.workID
        lessonAssignmentID = note.lessonAssignmentID
        attendanceRecordID = note.attendanceRecordID
        workCheckInID = note.workCheckInID
        workCompletionRecordID = note.workCompletionRecordID
        studentMeetingID = note.studentMeetingID
        projectSessionID = note.projectSessionID
        issueID = note.issueID
    }
}

// MARK: - Backup/Import/BackupEntityImporter+Todo.swift

// MARK: - Todo

extension LegacyBackupEntityImporter {

    // MARK: - Todo Items

    static func importTodoItems(
        _ dtos: [LegacyTodoItemDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDTodoItem>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let t = current ?? CDTodoItem(context: viewContext)
            t.id = dto.id
            t.title = dto.title
            t.notes = dto.notes
            t.createdAt = dto.createdAt
            t.orderIndex = Int64(dto.orderIndex)
            t.isCompleted = dto.isCompleted
            t.completedAt = dto.completedAt
            t.dueDate = dto.dueDate
            t.priority = TodoPriority(rawValue: dto.priorityRaw) ?? .none
            t.recurrence = RecurrencePattern(rawValue: dto.recurrenceRaw) ?? .none
            t.studentIDs = dto.studentIDs as NSObject
            t.linkedWorkItemID = dto.linkedWorkItemID
            t.attachmentPaths = dto.attachmentPaths as NSObject
            t.estimatedMinutes = Int64(dto.estimatedMinutes ?? 0)
            t.actualMinutes = Int64(dto.actualMinutes ?? 0)
            t.reminderDate = dto.reminderDate
            t.reflectionNotes = dto.reflectionNotes
            t.tags = dto.tags as NSObject
            t.scheduledDate = dto.scheduledDate
            t.isSomeday = dto.isSomeday ?? false
            t.repeatAfterCompletion = dto.repeatAfterCompletion ?? false
            t.customIntervalDays = Int64(dto.customIntervalDays ?? 0)
            t.locationName = dto.locationName
            t.locationLatitude = dto.locationLatitude ?? 0
            t.locationLongitude = dto.locationLongitude ?? 0
            t.locationRadius = dto.locationRadius
            t.notifyOnEntry = dto.notifyOnEntry
            t.notifyOnExit = dto.notifyOnExit
            t.moodRaw = dto.moodRaw
            // Kept as the backup has it, so a restored to-do isn't sent to
            // Tide a second time (a v40 or older backup keeps the record's
            // own: `BackupFieldsAddedLater`). A merge never blanks a link the
            // record has since gained: a backup taken before the to-do was
            // shared has none, and the sync would send it again as new. A
            // Replace restore starts from an empty store, so it is exact.
            if let link = dto.tideLink { t.tideLink = link }
            return t
        })
    }

    // MARK: - Today Agenda Orders

    static func importTodayAgendaOrders(
        _ dtos: [LegacyTodayAgendaOrderDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDTodayAgendaOrder>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let a = current ?? CDTodayAgendaOrder(context: viewContext)
            a.id = dto.id
            a.day = dto.day
            a.itemTypeRaw = (AgendaItemType(rawValue: dto.itemTypeRaw) ?? .lesson).rawValue
            a.itemID = dto.itemID
            a.position = Int64(dto.position)
            return a
        })
    }
}

// MARK: - Backup/Import/BackupEntityImporter+Tracks.swift

// MARK: - CDTrackEntity/Group Imports

extension LegacyBackupEntityImporter {

    // MARK: - Group Tracks

    static func importSequenceTracks(
        _ dtos: [LegacySequenceTrackDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDSequenceTrack>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let g = current ?? CDSequenceTrack(context: viewContext)
            g.id = dto.id
            g.area = dto.area
            g.sequence = dto.sequence
            g.isSequential = dto.isSequential
            g.isExplicitlyDisabled = dto.isExplicitlyDisabled
            g.createdAt = dto.createdAt
            return g
        })
    }
}
