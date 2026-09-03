// CoreDataIdentifiable.swift
// Identifiable conformance for Core Data entities with UUID? id.

import Foundation
import CoreData

nonisolated extension CDStudent: Identifiable {}
nonisolated extension CDLesson: Identifiable {}
nonisolated extension CDNote: Identifiable {}
nonisolated extension CDWorkModel: Identifiable {}
nonisolated extension CDLessonAssignment: Identifiable {}
nonisolated extension CDAttendanceRecord: Identifiable {}
nonisolated extension CDIssue: Identifiable {}
nonisolated extension CDProcedure: Identifiable {}
nonisolated extension CDPracticeSession: Identifiable {}
nonisolated extension CDStudentMeeting: Identifiable {}
nonisolated extension CDCommunityTopicEntity: Identifiable {}
nonisolated extension CDTrackEntity: Identifiable {}
nonisolated extension CDTrackStepEntity: Identifiable {}
nonisolated extension CDSampleWorkEntity: Identifiable {}
nonisolated extension CDTodoItemEntity: Identifiable {}
nonisolated extension CDTodoSubtaskEntity: Identifiable {}
nonisolated extension CDTodoTemplateEntity: Identifiable {}
nonisolated extension CDProject: Identifiable {}
nonisolated extension CDProjectSession: Identifiable {}
nonisolated extension CDProjectRole: Identifiable {}
nonisolated extension CDStudentTrackEnrollmentEntity: Identifiable {}
nonisolated extension CDWorkCheckIn: Identifiable {}
nonisolated extension CDSchedule: Identifiable {}
nonisolated extension CDScheduleSlot: Identifiable {}
nonisolated extension CDScheduledMeeting: Identifiable {}
nonisolated extension CDReminder: Identifiable {}
nonisolated extension CDMeetingTemplateEntity: Identifiable {}
nonisolated extension CDNoteTemplateEntity: Identifiable {}
nonisolated extension CDSupply: Identifiable {}
nonisolated extension CDDocument: Identifiable {}
nonisolated extension CDProposedSolutionEntity: Identifiable {}
nonisolated extension CDCommunityAttachmentEntity: Identifiable {}
nonisolated extension CDWorkCompletionRecord: Identifiable {}
nonisolated extension CDWorkStep: Identifiable {}
nonisolated extension CDResource: Identifiable {}
nonisolated extension CDParentCommunication: Identifiable {}
nonisolated extension CDGuardian: Identifiable {}
nonisolated extension CDMeetingWorkReview: Identifiable {}
nonisolated extension CDStudentFocusItem: Identifiable {}
nonisolated extension CDBookClubPacket: Identifiable {}
nonisolated extension CDBookClubSession: Identifiable {}
nonisolated extension CDBookClubMeeting: Identifiable {}
nonisolated extension CDAlbumBookmark: Identifiable {}
nonisolated extension CDAlbumPageNote: Identifiable {}
nonisolated extension CDAlbumRecentVisit: Identifiable {}
nonisolated extension CDAlbumReadingPosition: Identifiable {}
nonisolated extension CDAlbumHighlight: Identifiable {}
nonisolated extension CDAlbumPageInk: Identifiable {}

// MARK: - CD short name convenience aliases

typealias CDTodoItem = CDTodoItemEntity
typealias CDTodoSubtask = CDTodoSubtaskEntity
typealias CDTodoTemplate = CDTodoTemplateEntity
typealias CDMeetingTemplate = CDMeetingTemplateEntity
typealias CDNoteTemplate = CDNoteTemplateEntity
typealias CDSequenceTrack = CDSequenceTrackEntity
typealias CDPresentation = CDLessonPresentation
typealias CDSampleWork = CDSampleWorkEntity
typealias CDSampleWorkStep = CDSampleWorkStepEntity
typealias CDCommunityAttachment = CDCommunityAttachmentEntity
typealias CDTrackStep = CDTrackStepEntity
