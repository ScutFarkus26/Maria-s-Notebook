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

        try BackupEntityImporter.importRows(
            rows(\.students), as: CDStudent.self, into: viewContext,
            existing: { try index.existing(CDStudent.self, id: $0) }
        )

        try BackupEntityImporter.importRows(
            rows(\.lessons), as: CDLesson.self, into: viewContext,
            existing: { try index.existing(CDLesson.self, id: $0) }
        )

        try BackupEntityImporter.importCommunityTopics(
            rows(\.communityTopics),
            into: viewContext,
            existing: { try index.existing(CDCommunityTopicEntity.self, id: $0) }
        )

        try BackupEntityImporter.importRows(
            rows(\.lessonAssignments), as: CDLessonAssignment.self, into: viewContext,
            existing: { try index.existing(CDLessonAssignment.self, id: $0) }
        )

        let notes = try rows(\.notes)
        noteLinks = BackupEntityImporter.importRows(
            notes, as: CDNote.self, into: viewContext,
            existing: { try index.existing(CDNote.self, id: $0) }
        )
        restoredNoteIDs = notes.map(\.id)
    }

    /// Re-links every restored note to the records it points at
    /// (`noteLinks`), once every type they can be is in: the restore calls it
    /// after the last type. Each link is set to the record found by its id,
    /// or to nothing; a failed lookup stops the restore.
    func relinkNotes() throws {
        let index = self.index
        try BackupEntityImporter.relinkDeferred(
            noteLinks,
            owner: { try index.related(CDNote.self, id: $0) },
            parents: [
                "work": { try index.related(CDWorkModel.self, id: $0) },
                "lessonAssignment": { try index.related(CDLessonAssignment.self, id: $0) },
                "workCheckIn": { try index.related(CDWorkCheckIn.self, id: $0) },
                "workCompletionRecord": { try index.related(CDWorkCompletionRecord.self, id: $0) },
                "studentMeeting": { try index.related(CDStudentMeeting.self, id: $0) },
                "projectSession": { try index.related(CDProjectSession.self, id: $0) },
                "issue": { try index.related(CDIssue.self, id: $0) }
            ]
        )
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
            existing: { try index.existing(CDProjectSession.self, id: $0) },
            projectCheck: { try index.related(CDProject.self, id: $0) }
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
    }

    func importLessonExtras() throws {
        let viewContext = context
        let index = self.index

        if let lessonAttachments = try rows(\.lessonAttachments) {
            // Before v44 a row has no `modifiedAt`; it reads as its `attachedAt`.
            // A merge keeps a record's own file when the row's has gone since
            // (a replace or a rename after the backup; `keepingLiveLessonFiles`).
            let lessonFiles = BackupLessonFiles.storage
            let attachmentRows = BackupEntityImporter.keepingLiveLessonFiles(
                index.predatedValues.standingIn(for: lessonAttachments),
                existing: { id in
                    BackupEntityImporter.existingEntity(id: id) { try index.existing(CDLessonAttachment.self, id: $0) }
                },
                isPresent: { BackupLessonFiles.isPresent($0, in: lessonFiles) }
            )
            BackupEntityImporter.importRows(
                attachmentRows,
                as: CDLessonAttachment.self, into: viewContext,
                existing: { try index.existing(CDLessonAttachment.self, id: $0) },
                parents: ["lesson": { try index.related(CDLesson.self, id: $0) }]
            )
        }

        if let lessonPresentations = try rows(\.lessonPresentations) {
            BackupEntityImporter.importRows(
                lessonPresentations, as: CDLessonPresentation.self, into: viewContext,
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
            BackupEntityImporter.importRows(
                sampleWorks, as: CDSampleWork.self, into: viewContext,
                existing: { try index.existing(CDSampleWork.self, id: $0) },
                parents: ["lesson": { try index.related(CDLesson.self, id: $0) }]
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
