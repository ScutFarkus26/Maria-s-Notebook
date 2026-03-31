// LegacyTypeAliases.swift
// Bridge typealiases from old SwiftData type names to Core Data entity classes.
// These allow existing code to compile during the transition.
// TODO: Phase 5+ cleanup — replace usages with canonical CD names and remove this file.

import Foundation
import CoreData

// MARK: - Identifiable conformance for Core Data entities with UUID? id

extension CDStudent: Identifiable {}
extension CDLesson: Identifiable {}
extension CDNote: Identifiable {}
extension CDWorkModel: Identifiable {}
extension CDLessonAssignment: Identifiable {}
extension CDAttendanceRecord: Identifiable {}
extension CDIssue: Identifiable {}
extension CDProcedure: Identifiable {}
extension CDPracticeSession: Identifiable {}
extension CDStudentMeeting: Identifiable {}
extension CDCommunityTopicEntity: Identifiable {}
extension CDTrackEntity: Identifiable {}
extension CDTrackStepEntity: Identifiable {}
extension CDSampleWorkEntity: Identifiable {}
extension CDTodoItemEntity: Identifiable {}
extension CDTodoSubtaskEntity: Identifiable {}
extension CDTodoTemplateEntity: Identifiable {}
extension CDProject: Identifiable {}
extension CDProjectTemplateWeek: Identifiable {}
extension CDProjectSession: Identifiable {}
extension CDProjectRole: Identifiable {}
extension CDProjectAssignmentTemplate: Identifiable {}
extension CDProjectWeekRoleAssignment: Identifiable {}
extension CDStudentTrackEnrollmentEntity: Identifiable {}
extension CDWorkCheckIn: Identifiable {}
extension CDSchedule: Identifiable {}
extension CDScheduleSlot: Identifiable {}
extension CDScheduledMeeting: Identifiable {}
extension CDReminder: Identifiable {}
extension CDMeetingTemplateEntity: Identifiable {}
extension CDNoteTemplateEntity: Identifiable {}
extension CDSupply: Identifiable {}
extension CDSupplyTransaction: Identifiable {}
extension CDDocument: Identifiable {}
extension CDProposedSolutionEntity: Identifiable {}
extension CDCommunityAttachmentEntity: Identifiable {}
extension CDTransitionChecklistItem: Identifiable {}
extension CDTransitionPlan: Identifiable {}
extension CDWorkCompletionRecord: Identifiable {}
extension CDWorkStep: Identifiable {}
extension CDResource: Identifiable {}

// MARK: - SwiftData name → Core Data entity

typealias Student = CDStudent
typealias Note = CDNote
typealias Lesson = CDLesson
typealias WorkModel = CDWorkModel
typealias Issue = CDIssue
typealias IssueAction = CDIssueAction
typealias Procedure = CDProcedure
typealias AttendanceRecord = CDAttendanceRecord
typealias StudentMeeting = CDStudentMeeting
typealias PracticeSession = CDPracticeSession
typealias WorkParticipantEntity = CDWorkParticipantEntity
typealias WorkCompletionRecord = CDWorkCompletionRecord
typealias DevelopmentSnapshot = CDDevelopmentSnapshotEntity
typealias LessonAttachment = CDLessonAttachment
typealias GoingOutChecklistItem = CDGoingOutChecklistItem
typealias PlanningRecommendation = CDPlanningRecommendation
typealias ProposedSolution = CDProposedSolutionEntity
typealias CommunityAttachment = CDCommunityAttachmentEntity
typealias StudentTrackEnrollment = CDStudentTrackEnrollmentEntity
typealias Track = CDTrackEntity
typealias TransitionChecklistItem = CDTransitionChecklistItem
typealias ProjectRole = CDProjectRole
typealias ProjectTemplateWeek = CDProjectTemplateWeek
typealias ProjectAssignmentTemplate = CDProjectAssignmentTemplate
typealias ProjectWeekRoleAssignment = CDProjectWeekRoleAssignment
typealias SupplyTransaction = CDSupplyTransaction
typealias CommunityTopic = CDCommunityTopicEntity
typealias SampleWork = CDSampleWorkEntity
typealias LessonAssignment = CDLessonAssignment
typealias ScheduledMeeting = CDScheduledMeeting
typealias WorkCheckIn = CDWorkCheckIn
typealias Reminder = CDReminder
typealias CalendarEvent = CDCalendarEvent
typealias TodayAgendaOrder = CDTodayAgendaOrder
typealias TrackStep = CDTrackStepEntity
typealias CDTrackStep = CDTrackStepEntity
typealias LessonPresentation = CDLessonPresentation
typealias GroupTrack = CDGroupTrackEntity
typealias TodoItem = CDTodoItemEntity
typealias Project = CDProject
typealias ProjectSession = CDProjectSession
typealias GoingOut = CDGoingOut
typealias Supply = CDSupply
typealias Document = CDDocument
typealias WorkStep = CDWorkStep
typealias SampleWorkStep = CDSampleWorkStepEntity
typealias Resource = CDResource

// MARK: - CD short name → CD full entity name (suffix normalization)

typealias CDTodoItem = CDTodoItemEntity
typealias CDTodoSubtask = CDTodoSubtaskEntity
typealias CDTodoTemplate = CDTodoTemplateEntity
typealias CDMeetingTemplate = CDMeetingTemplateEntity
typealias CDNoteTemplate = CDNoteTemplateEntity
typealias CDGroupTrack = CDGroupTrackEntity
typealias CDPresentation = CDLessonPresentation
typealias CDSampleWork = CDSampleWorkEntity
typealias CDSampleWorkStep = CDSampleWorkStepEntity
typealias CDCommunityAttachment = CDCommunityAttachmentEntity

// MARK: - SwiftData utility types (stub classes for backup compatibility)
// These were SwiftData-only models without Core Data entities in the .xcdatamodeld.
// They exist only so backup import/export code compiles. No data is stored.

final class AlbumGroupOrder: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var albumID: String?
    @NSManaged var scopeKey: String?
    @NSManaged var groupName: String?
    @NSManaged var sortIndex: Int64
    @NSManaged var sortOrder: Int64
}

final class AlbumGroupUIState: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var albumID: String?
    @NSManaged var scopeKey: String?
    @NSManaged var groupName: String?
    @NSManaged var isCollapsed: Bool
    @NSManaged var isExpanded: Bool
}
