// BackupRestoreRun+PlanningTypes.swift
// The restore order, second part: templates and calendar events,
// tracks, documents and supplies, schedules, issues, snapshots and todos,
// recommendations, resources and note-student links.

import CoreData
import Foundation

extension BackupRestoreRun {

    func importTemplateEntities() throws {
        let viewContext = context
        let index = self.index

        if let meetingTemplates = try rows(\.meetingTemplates) {
            BackupEntityImporter.importRows(
                meetingTemplates, as: CDMeetingTemplate.self, into: viewContext,
                existing: { try index.existing(CDMeetingTemplate.self, id: $0) }
            )
        }

        // Calendar events are copies of the device's Apple Calendar, carried
        // but never restored (`BackupEntityRegistry.keptOnRestoreEntityNames`):
        // the next sync rebuilds them. Taking them still frees them in type order.
        _ = try rows(\.calendarEvents)
    }

    func importTrackEntities() throws {
        let viewContext = context
        let index = self.index

        if let tracks = try rows(\.tracks) {
            BackupEntityImporter.importRows(
                tracks, as: CDTrackEntity.self, into: viewContext,
                existing: { try index.existing(CDTrackEntity.self, id: $0) }
            )
        }

        if let trackSteps = try rows(\.trackSteps) {
            BackupEntityImporter.importRows(
                trackSteps, as: CDTrackStep.self, into: viewContext,
                existing: { try index.existing(CDTrackStep.self, id: $0) },
                parents: ["track": { try index.related(CDTrackEntity.self, id: $0) }]
            )
        }

        if let enrollments = try rows(\.studentTrackEnrollments) {
            BackupEntityImporter.importRows(
                enrollments, as: CDStudentTrackEnrollmentEntity.self, into: viewContext,
                existing: { try index.existing(CDStudentTrackEnrollmentEntity.self, id: $0) },
                parents: ["track": { try index.related(CDTrackEntity.self, id: $0) }]
            )
        }

        if let sequenceTracks = try rows(\.sequenceTracks) {
            BackupEntityImporter.importRows(
                sequenceTracks, as: CDSequenceTrack.self, into: viewContext,
                existing: { try index.existing(CDSequenceTrack.self, id: $0) }
            )
        }
    }

    func importDocumentEntities() throws {
        let viewContext = context
        let index = self.index

        if let documents = try rows(\.documents) {
            BackupEntityImporter.importRows(
                documents, as: CDDocument.self, into: viewContext,
                existing: { try index.existing(CDDocument.self, id: $0) }
            )
        }

        if let supplies = try rows(\.supplies) {
            BackupEntityImporter.importRows(
                supplies, as: CDSupply.self, into: viewContext,
                existing: { try index.existing(CDSupply.self, id: $0) }
            )
        }

        if let procedures = try rows(\.procedures) {
            BackupEntityImporter.importRows(
                procedures, as: CDProcedure.self, into: viewContext,
                existing: { try index.existing(CDProcedure.self, id: $0) }
            )
        }
    }

    func importScheduleEntities() throws {
        let viewContext = context
        let index = self.index

        if let schedules = try rows(\.schedules) {
            BackupEntityImporter.importRows(
                schedules, as: CDSchedule.self, into: viewContext,
                existing: { try index.existing(CDSchedule.self, id: $0) }
            )
        }

        if let scheduleSlots = try rows(\.scheduleSlots) {
            BackupEntityImporter.importRows(
                scheduleSlots, as: CDScheduleSlot.self, into: viewContext,
                existing: { try index.existing(CDScheduleSlot.self, id: $0) },
                parents: ["schedule": { try index.related(CDSchedule.self, id: $0) }]
            )
        }
    }

    func importIssueEntities() throws {
        let viewContext = context
        let index = self.index

        if let issues = try rows(\.issues) {
            BackupEntityImporter.importRows(
                issues, as: CDIssue.self, into: viewContext,
                existing: { try index.existing(CDIssue.self, id: $0) }
            )
        }

        if let issueActions = try rows(\.issueActions) {
            BackupEntityImporter.importRows(
                issueActions, as: CDIssueAction.self, into: viewContext,
                existing: { try index.existing(CDIssueAction.self, id: $0) },
                parents: ["issue": { try index.related(CDIssue.self, id: $0) }]
            )
        }
    }

    func importSnapshotAndTodoEntities() throws {
        let viewContext = context
        let index = self.index

        if let snapshots = try rows(\.developmentSnapshots) {
            BackupEntityImporter.importRows(
                snapshots, as: CDDevelopmentSnapshotEntity.self, into: viewContext,
                existing: { try index.existing(CDDevelopmentSnapshotEntity.self, id: $0) }
            )
        }

        if let todoItems = try rows(\.todoItems) {
            BackupEntityImporter.importRows(
                todoItems, as: CDTodoItem.self, into: viewContext,
                existing: { try index.existing(CDTodoItem.self, id: $0) }
            )
        }

        if let agendaOrders = try rows(\.todayAgendaOrders) {
            BackupEntityImporter.importRows(
                agendaOrders, as: CDTodayAgendaOrder.self, into: viewContext,
                existing: { try index.existing(CDTodayAgendaOrder.self, id: $0) }
            )
        }
    }

    func importAdditionalEntities() throws {
        let viewContext = context
        let index = self.index

        if let recommendations = try rows(\.planningRecommendations) {
            BackupEntityImporter.importRows(
                recommendations, as: CDPlanningRecommendation.self, into: viewContext,
                existing: { try index.existing(CDPlanningRecommendation.self, id: $0) }
            )
        }

        if let resources = try rows(\.resources) {
            BackupEntityImporter.importRows(
                resources, as: CDResource.self, into: viewContext,
                existing: { try index.existing(CDResource.self, id: $0) }
            )
        }

        if var noteStudentLinks = try rows(\.noteStudentLinks) {
            // A note a Merge kept as it is here keeps its own links.
            if !keptNoteIDs.isEmpty {
                noteStudentLinks.removeAll { link in
                    link.string("noteID").flatMap(UUID.init(uuidString:)).map(keptNoteIDs.contains) == true
                }
            }
            BackupEntityImporter.importRows(
                noteStudentLinks, as: CDNoteStudentLink.self, into: viewContext,
                existing: { try index.existing(CDNoteStudentLink.self, id: $0) },
                parents: ["note": { try index.related(CDNote.self, id: $0) }]
            )
            restoredLinkIDs = Set(noteStudentLinks.map(\.id))
        }
    }
}
