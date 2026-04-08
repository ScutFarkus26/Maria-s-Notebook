// CoreDataIdentifiable.swift
// Identifiable conformance for Core Data entities with UUID? id.

import Foundation
import CoreData

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
extension CDParentCommunication: Identifiable {}
extension CDPrepChecklist: Identifiable {}
extension CDPrepChecklistItem: Identifiable {}
extension CDPrepChecklistCompletion: Identifiable {}

// MARK: - CD short name convenience aliases

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
typealias CDTrackStep = CDTrackStepEntity
