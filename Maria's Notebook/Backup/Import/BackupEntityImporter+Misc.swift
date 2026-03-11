import Foundation
import SwiftData

// MARK: - Miscellaneous Entities

extension BackupEntityImporter {

    // MARK: - Notes

    /// Imports notes from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The note DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a note already exists
    ///   - lessonCheck: Function to look up a lesson by ID for linking
    static func importNotes(
        _ dtos: [NoteDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Note>,
        lessonCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check existing note: \(error)")
                continue
            }

            // Determine tags: prefer dto.tags, fallback to converting legacy categoryRaw if present
            let importedTags: [String]
            if let dtoTags = dto.tags, !dtoTags.isEmpty {
                importedTags = dtoTags
            } else {
                importedTags = []
            }

            let note = Note(
                id: dto.id,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                body: dto.body,
                tags: importedTags,
                needsFollowUp: dto.needsFollowUp ?? false,
                imagePath: dto.imagePath
            )
            note.isPinned = dto.isPinned

            if let data = dto.scope.data(using: .utf8) {
                do {
                    let scope = try JSONDecoder().decode(NoteScope.self, from: data)
                    note.scope = scope
                } catch {
                    print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to decode note scope: \(error)")
                }
            }

            if let lessonID = dto.lessonID {
                do {
                    if let lesson = try lessonCheck(lessonID) {
                        note.lesson = lesson
                    }
                } catch {
                    print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check lesson for note: \(error)")
                }
            }

            modelContext.insert(note)
        }
    }

    // MARK: - Note Templates

    static func importNoteTemplates(
        _ dtos: [NoteTemplateDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<NoteTemplate>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
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
            return NoteTemplate(
                id: dto.id,
                createdAt: dto.createdAt,
                title: dto.title,
                body: dto.body,
                tags: templateTags,
                sortOrder: dto.sortOrder,
                isBuiltIn: dto.isBuiltIn
            )
        })
    }

    // MARK: - Community Topics

    /// Imports community topics from DTOs.
    static func importCommunityTopics(
        _ dtos: [CommunityTopicDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<CommunityTopic>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let topic = CommunityTopic(
                id: dto.id, title: dto.title,
                issueDescription: dto.issueDescription,
                createdAt: dto.createdAt,
                addressedDate: dto.addressedDate,
                resolution: dto.resolution
            )
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
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a solution already exists
    ///   - topicCheck: Function to look up a community topic by ID
    static func importProposedSolutions(
        _ dtos: [ProposedSolutionDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProposedSolution>,
        topicCheck: EntityExistsCheck<CommunityTopic>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check existing proposed solution: \(error)")
                continue
            }

            let solution = ProposedSolution(
                id: dto.id,
                title: dto.title,
                details: dto.details,
                proposedBy: dto.proposedBy,
                createdAt: dto.createdAt,
                isAdopted: dto.isAdopted,
                topic: nil
            )

            if let topicID = dto.topicID {
                do {
                    if let topic = try topicCheck(topicID) {
                        solution.topic = topic
                    }
                } catch {
                        // swiftlint:disable:next line_length
                    print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check topic for proposed solution: \(error)")
                }
            }

            modelContext.insert(solution)
        }
    }

    // MARK: - Community Attachments

    /// Imports community attachments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The community attachment DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if an attachment already exists
    ///   - topicCheck: Function to look up a community topic by ID
    static func importCommunityAttachments(
        _ dtos: [CommunityAttachmentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<CommunityAttachment>,
        topicCheck: EntityExistsCheck<CommunityTopic>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check existing community attachment: \(error)")
                continue
            }

            let attachment = CommunityAttachment(
                id: dto.id,
                filename: dto.filename,
                kind: CommunityAttachment.Kind(rawValue: dto.kind) ?? .file,
                data: nil,
                createdAt: dto.createdAt,
                topic: nil
            )

            if let topicID = dto.topicID {
                do {
                    if let topic = try topicCheck(topicID) {
                        attachment.topic = topic
                    }
                } catch {
                        // swiftlint:disable:next line_length
                    print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check topic for community attachment: \(error)")
                }
            }

            modelContext.insert(attachment)
        }
    }

    // MARK: - Issues

    static func importIssues(
        _ dtos: [IssueDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Issue>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let i = Issue(
                title: dto.title,
                description: dto.issueDescription,
                category: IssueCategory(rawValue: dto.categoryRaw) ?? .other,
                priority: IssuePriority(rawValue: dto.priorityRaw) ?? .medium,
                status: IssueStatus(rawValue: dto.statusRaw) ?? .open,
                studentIDs: dto.studentIDs,
                location: dto.location
            )
            i.id = dto.id
            i.createdAt = dto.createdAt
            i.updatedAt = dto.updatedAt
            i.modifiedAt = dto.modifiedAt
            i.resolvedAt = dto.resolvedAt
            i.resolutionSummary = dto.resolutionSummary
            return i
        })
    }

    // MARK: - Issue Actions

    static func importIssueActions(
        _ dtos: [IssueActionDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<IssueAction>,
        issueCheck: EntityExistsCheck<Issue>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let a = IssueAction(
                actionType: IssueActionType(rawValue: dto.actionTypeRaw) ?? .note,
                description: dto.actionDescription,
                actionDate: dto.actionDate,
                participantStudentIDs: dto.participantStudentIDs,
                nextSteps: dto.nextSteps,
                followUpRequired: dto.followUpRequired,
                followUpDate: dto.followUpDate
            )
            a.id = dto.id
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
                    print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check issue for action: \(error)")
                }
            }
            modelContext.insert(a)
        }
    }

    // MARK: - Development Snapshots

    static func importDevelopmentSnapshots(
        _ dtos: [DevelopmentSnapshotDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<DevelopmentSnapshot>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let s = DevelopmentSnapshot(
                id: dto.id,
                studentID: dto.studentID,
                generatedAt: dto.generatedAt,
                lookbackDays: dto.lookbackDays,
                analysisVersion: dto.analysisVersion,
                overallProgress: dto.overallProgress,
                keyStrengths: dto.keyStrengths,
                areasForGrowth: dto.areasForGrowth,
                developmentalMilestones: dto.developmentalMilestones,
                observedPatterns: dto.observedPatterns,
                behavioralTrends: dto.behavioralTrends,
                socialEmotionalInsights: dto.socialEmotionalInsights,
                recommendedNextLessons: dto.recommendedNextLessons,
                suggestedPracticeFocus: dto.suggestedPracticeFocus,
                interventionSuggestions: dto.interventionSuggestions,
                totalNotesAnalyzed: dto.totalNotesAnalyzed,
                practiceSessionsAnalyzed: dto.practiceSessionsAnalyzed,
                workCompletionsAnalyzed: dto.workCompletionsAnalyzed,
                averagePracticeQuality: dto.averagePracticeQuality,
                independenceLevel: dto.independenceLevel,
                rawAnalysisJSON: dto.rawAnalysisJSON
            )
            s.userNotes = dto.userNotes
            s.isReviewed = dto.isReviewed
            s.sharedWithParents = dto.sharedWithParents
            s.sharedAt = dto.sharedAt
            return s
        })
    }

    // MARK: - PlanningRecommendation

    static func importPlanningRecommendations(
        _ dtos: [PlanningRecommendationDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<PlanningRecommendation>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let lessonUUID = UUID(uuidString: dto.lessonID),
                  let sessionUUID = UUID(uuidString: dto.planningSessionID),
                  let depth = PlanningDepth(rawValue: dto.depthLevel) else { continue }
            // Decode student IDs from the blob
            let studentIDs = CloudKitStringArrayStorage.decode(from: dto.studentIDsData)
                .compactMap { UUID(uuidString: $0) }
            let rec = PlanningRecommendation(
                lessonID: lessonUUID,
                studentIDs: studentIDs,
                reasoning: dto.reasoning,
                confidence: dto.confidence,
                priority: dto.priority,
                subjectContext: dto.subjectContext,
                groupContext: dto.groupContext,
                planningSessionID: sessionUUID,
                depthLevel: depth
            )
            // Overwrite generated fields with backup values
            rec.id = dto.id
            rec.createdAt = dto.createdAt
            rec.modifiedAt = dto.modifiedAt
            rec.decisionRaw = dto.decisionRaw
            rec.decisionAt = dto.decisionAt
            rec.teacherNote = dto.teacherNote
            rec.outcomeRaw = dto.outcomeRaw
            rec.outcomeRecordedAt = dto.outcomeRecordedAt
            rec.presentationID = dto.presentationID
            modelContext.insert(rec)
        }
    }

}
