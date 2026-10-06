// BackupRestoreRun+PlanningTypes.swift
// The restore order, second part: templates, reminders and calendar events,
// tracks, documents and supplies, schedules, issues, snapshots and todos,
// recommendations, resources and note-student links.

import CoreData
import Foundation

extension BackupRestoreRun {

    func importTemplateEntities() throws {
        let viewContext = context
        let index = self.index

        if let noteTemplates = try rows(\.noteTemplates) {
            try BackupEntityImporter.importNoteTemplates(
                noteTemplates,
                into: viewContext,
                existing: { try index.existing(CDNoteTemplate.self, id: $0) }
            )
        }

        if let meetingTemplates = try rows(\.meetingTemplates) {
            BackupEntityImporter.importRows(
                meetingTemplates, as: CDMeetingTemplate.self, into: viewContext,
                existing: { try index.existing(CDMeetingTemplate.self, id: $0) }
            )
        }

        // Reminders and calendar events are copies of the device's EventKit
        // lists, carried but never restored
        // (`BackupEntityRegistry.keptOnRestoreEntityNames`): the next sync
        // rebuilds them. Taking them still frees them in type order.
        _ = try rows(\.reminders)
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
            try BackupEntityImporter.importSequenceTracks(
                sequenceTracks,
                into: viewContext,
                existing: { try index.existing(CDSequenceTrack.self, id: $0) }
            )
        }
    }

    func importDocumentEntities() throws {
        let viewContext = context
        let index = self.index

        if let documents = try rows(\.documents) {
            try BackupEntityImporter.importDocuments(
                documents,
                into: viewContext,
                existing: { try index.existing(CDDocument.self, id: $0) }
            )
        }

        if let supplies = try rows(\.supplies) {
            try BackupEntityImporter.importSupplies(
                supplies,
                into: viewContext,
                existing: { try index.existing(CDSupply.self, id: $0) }
            )
        }

        if let procedures = try rows(\.procedures) {
            try BackupEntityImporter.importProcedures(
                procedures,
                into: viewContext,
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
            try BackupEntityImporter.importScheduleSlots(
                scheduleSlots,
                into: viewContext,
                existing: { try index.existing(CDScheduleSlot.self, id: $0) },
                scheduleCheck: { try index.related(CDSchedule.self, id: $0) }
            )
        }
    }

    func importIssueEntities() throws {
        let viewContext = context
        let index = self.index

        if let issues = try rows(\.issues) {
            try BackupEntityImporter.importIssues(
                issues,
                into: viewContext,
                existing: { try index.existing(CDIssue.self, id: $0) }
            )
        }

        if let issueActions = try rows(\.issueActions) {
            try BackupEntityImporter.importIssueActions(
                issueActions,
                into: viewContext,
                existing: { try index.existing(CDIssueAction.self, id: $0) },
                issueCheck: { try index.related(CDIssue.self, id: $0) }
            )
        }
    }

    func importSnapshotAndTodoEntities() throws {
        let viewContext = context
        let index = self.index

        if let snapshots = try rows(\.developmentSnapshots) {
            try BackupEntityImporter.importDevelopmentSnapshots(
                snapshots,
                into: viewContext,
                existing: { try index.existing(CDDevelopmentSnapshotEntity.self, id: $0) }
            )
        }

        if let todoItems = try rows(\.todoItems) {
            try BackupEntityImporter.importTodoItems(
                todoItems,
                into: viewContext,
                existing: { try index.existing(CDTodoItem.self, id: $0) }
            )
        }

        if let todoSubtasks = try rows(\.todoSubtasks) {
            BackupEntityImporter.importRows(
                todoSubtasks, as: CDTodoSubtask.self, into: viewContext,
                existing: { try index.existing(CDTodoSubtask.self, id: $0) },
                parents: ["todo": { try index.related(CDTodoItem.self, id: $0) }]
            )
        }

        if let todoTemplates = try rows(\.todoTemplates) {
            try BackupEntityImporter.importTodoTemplates(
                todoTemplates,
                into: viewContext,
                existing: { try index.existing(CDTodoTemplate.self, id: $0) }
            )
        }

        if let agendaOrders = try rows(\.todayAgendaOrders) {
            try BackupEntityImporter.importTodayAgendaOrders(
                agendaOrders,
                into: viewContext,
                existing: { try index.existing(CDTodayAgendaOrder.self, id: $0) }
            )
        }
    }

    func importAdditionalEntities() throws {
        let viewContext = context
        let index = self.index

        if let recommendations = try rows(\.planningRecommendations) {
            try BackupEntityImporter.importPlanningRecommendations(
                recommendations,
                into: viewContext,
                existing: { try index.existing(CDPlanningRecommendation.self, id: $0) }
            )
        }

        if let resources = try rows(\.resources) {
            try BackupEntityImporter.importResources(
                resources,
                into: viewContext,
                existing: { try index.existing(CDResource.self, id: $0) }
            )
        }

        if let noteStudentLinks = try rows(\.noteStudentLinks) {
            BackupEntityImporter.importRows(
                noteStudentLinks, as: CDNoteStudentLink.self, into: viewContext,
                existing: { try index.existing(CDNoteStudentLink.self, id: $0) },
                parents: ["note": { try index.related(CDNote.self, id: $0) }]
            )
            restoredLinkIDs = Set(noteStudentLinks.map(\.id))
        }
    }
}
