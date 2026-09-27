// BackupRestoreRun+CoreTypes.swift
// The restore order, first part: people, lessons, notes, the calendar and
// records, projects, work, and lesson extras. `BackupService.importRows` calls
// these in order; each type is read from the source only when its importer
// runs, so parents are in the store (and in `index`) before their children.

import CoreData
import Foundation

extension BackupRestoreRun {

    func importCoreEntities() throws {
        let viewContext = context
        let index = self.index

        _ = try BackupEntityImporter.importStudents(
            rows(\.students),
            into: viewContext,
            existing: { try index.existing(CDStudent.self, id: $0) }
        )

        try BackupEntityImporter.importLessons(
            rows(\.lessons),
            into: viewContext,
            existing: { try index.existing(CDLesson.self, id: $0) }
        )

        try BackupEntityImporter.importCommunityTopics(
            rows(\.communityTopics),
            into: viewContext,
            existing: { try index.existing(CDCommunityTopicEntity.self, id: $0) }
        )

        try BackupEntityImporter.importLessonAssignments(
            rows(\.lessonAssignments),
            into: viewContext,
            existing: { try index.existing(CDLessonAssignment.self, id: $0) },
            lessonCheck: { try index.related(CDLesson.self, id: $0) }
        )

        let notes = try rows(\.notes)
        try BackupEntityImporter.importNotes(
            notes,
            into: viewContext,
            existing: { try index.existing(CDNote.self, id: $0) }
        )
        noteLinks = notes.compactMap(BackupNoteLinks.init)
    }

    func importCalendarAndRecordEntities() throws {
        let viewContext = context
        let index = self.index

        try BackupEntityImporter.importNonSchoolDays(
            rows(\.nonSchoolDays),
            into: viewContext,
            existing: { try index.existing(CDNonSchoolDay.self, id: $0) }
        )

        try BackupEntityImporter.importSchoolDayOverrides(
            rows(\.schoolDayOverrides),
            into: viewContext,
            existing: { try index.existing(CDSchoolDayOverride.self, id: $0) }
        )

        try BackupEntityImporter.importStudentMeetings(
            rows(\.studentMeetings),
            into: viewContext,
            existing: { try index.existing(CDStudentMeeting.self, id: $0) }
        )

        try BackupEntityImporter.importRows(
            rows(\.proposedSolutions), as: CDProposedSolutionEntity.self, into: viewContext,
            existing: { try index.existing(CDProposedSolutionEntity.self, id: $0) },
            parents: ["topic": { try index.related(CDCommunityTopicEntity.self, id: $0) }]
        )

        try BackupEntityImporter.importCommunityAttachments(
            rows(\.communityAttachments),
            into: viewContext,
            existing: { try index.existing(CDCommunityAttachment.self, id: $0) },
            topicCheck: { try index.related(CDCommunityTopicEntity.self, id: $0) }
        )

        try BackupEntityImporter.importAttendanceRecords(
            rows(\.attendance),
            into: viewContext,
            existing: { try index.existing(CDAttendanceRecord.self, id: $0) }
        )

        try BackupEntityImporter.importWorkCompletionRecords(
            rows(\.workCompletions),
            into: viewContext,
            existing: { try index.existing(CDWorkCompletionRecord.self, id: $0) }
        )
    }

    func importProjectEntities() throws {
        let viewContext = context
        let index = self.index

        try BackupEntityImporter.importProjects(
            rows(\.projects),
            into: viewContext,
            existing: { try index.existing(CDProject.self, id: $0) }
        )

        try BackupEntityImporter.importProjectRoles(
            rows(\.projectRoles),
            into: viewContext,
            existing: { try index.existing(CDProjectRole.self, id: $0) }
        )

        // Import of CDProjectTemplateWeek, CDProjectAssignmentTemplate, and
        // CDProjectWeekRoleAssignment skipped — entities deprecated.

        try BackupEntityImporter.importProjectSessions(
            rows(\.projectSessions),
            into: viewContext,
            existing: { try index.existing(CDProjectSession.self, id: $0) }
        )
    }

    func importWorkTrackingEntities() throws {
        let viewContext = context
        let index = self.index

        // CDWorkModel must be imported first — child entities reference it
        if let workModels = try rows(\.workModels) {
            try BackupEntityImporter.importWorkModels(
                workModels,
                into: viewContext,
                existing: { try index.existing(CDWorkModel.self, id: $0) }
            )
        }

        if let workCheckIns = try rows(\.workCheckIns) {
            try BackupEntityImporter.importWorkCheckIns(
                workCheckIns,
                into: viewContext,
                existing: { try index.existing(CDWorkCheckIn.self, id: $0) },
                workCheck: { try index.related(CDWorkModel.self, id: $0) }
            )
        }

        if let workSteps = try rows(\.workSteps) {
            BackupEntityImporter.importRows(
                workSteps, as: CDWorkStep.self, into: viewContext,
                existing: { try index.existing(CDWorkStep.self, id: $0) },
                parents: ["work": { try index.related(CDWorkModel.self, id: $0) }]
            )
        }

        if let workParticipants = try rows(\.workParticipants) {
            try BackupEntityImporter.importWorkParticipants(
                workParticipants,
                into: viewContext,
                existing: { try index.existing(CDWorkParticipantEntity.self, id: $0) },
                workCheck: { try index.related(CDWorkModel.self, id: $0) }
            )
        }

        if let practiceSessions = try rows(\.practiceSessions) {
            try BackupEntityImporter.importPracticeSessions(
                practiceSessions,
                into: viewContext,
                existing: { try index.existing(CDPracticeSession.self, id: $0) }
            )
        }
    }

    func importLessonExtras() throws {
        let viewContext = context
        let index = self.index

        if let lessonAttachments = try rows(\.lessonAttachments) {
            BackupEntityImporter.importRows(
                lessonAttachments, as: CDLessonAttachment.self, into: viewContext,
                existing: { try index.existing(CDLessonAttachment.self, id: $0) },
                parents: ["lesson": { try index.related(CDLesson.self, id: $0) }]
            )
        }

        if let lessonPresentations = try rows(\.lessonPresentations) {
            try BackupEntityImporter.importLessonPresentations(
                lessonPresentations,
                into: viewContext,
                existing: { try index.existing(CDLessonPresentation.self, id: $0) }
            )
        }

        if let recallChecks = try rows(\.recallChecks) {
            BackupEntityImporter.importRows(
                recallChecks, as: CDLessonRecallCheck.self, into: viewContext,
                existing: { try index.existing(CDLessonRecallCheck.self, id: $0) }
            )
        }

        if let sampleWorks = try rows(\.sampleWorks) {
            try BackupEntityImporter.importSampleWorks(
                sampleWorks,
                into: viewContext,
                existing: { try index.existing(CDSampleWork.self, id: $0) },
                lessonCheck: { try index.related(CDLesson.self, id: $0) }
            )
        }

        if let sampleWorkSteps = try rows(\.sampleWorkSteps) {
            BackupEntityImporter.importRows(
                sampleWorkSteps, as: CDSampleWorkStep.self, into: viewContext,
                existing: { try index.existing(CDSampleWorkStep.self, id: $0) },
                parents: ["sampleWork": { try index.related(CDSampleWork.self, id: $0) }]
            )
        }
    }
}
