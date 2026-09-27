// BackupRestoreRun+LaterTypes.swift
// The restore order, last part: the format v12–v14 types, then v18 (stories,
// book club, year plan, day pads), v20 (guardians, parent communications), v21
// (teaching-album annotations) and v27 (orders).

import CoreData
import Foundation

extension BackupRestoreRun {

    func importV12Entities() throws {
        let viewContext = context
        let index = self.index

        if let goingOuts = try rows(\.goingOuts) {
            BackupEntityImporter.importRows(
                goingOuts, as: CDGoingOut.self, into: viewContext,
                existing: { try index.existing(CDGoingOut.self, id: $0) }
            )
        }

        if let goingOutItems = try rows(\.goingOutChecklistItems) {
            try BackupEntityImporter.importGoingOutChecklistItems(
                goingOutItems,
                into: viewContext,
                existing: { try index.existing(CDGoingOutChecklistItem.self, id: $0) },
                goingOutCheck: { try index.related(CDGoingOut.self, id: $0) }
            )
        }

        if let classroomJobs = try rows(\.classroomJobs) {
            BackupEntityImporter.importRows(
                classroomJobs, as: CDClassroomJob.self, into: viewContext,
                existing: { try index.existing(CDClassroomJob.self, id: $0) }
            )
        }

        if let jobAssignments = try rows(\.jobAssignments) {
            BackupEntityImporter.importRows(
                jobAssignments, as: CDJobAssignment.self, into: viewContext,
                existing: { try index.existing(CDJobAssignment.self, id: $0) },
                parents: ["job": { try index.related(CDClassroomJob.self, id: $0) }]
            )
        }

        if let calendarNotes = try rows(\.calendarNotes) {
            BackupEntityImporter.importRows(
                calendarNotes, as: CDCalendarNote.self, into: viewContext,
                existing: { try index.existing(CDCalendarNote.self, id: $0) }
            )
        }

        if let scheduledMeetings = try rows(\.scheduledMeetings) {
            try BackupEntityImporter.importScheduledMeetings(
                scheduledMeetings,
                into: viewContext,
                existing: { try index.existing(CDScheduledMeeting.self, id: $0) }
            )
        }
    }

    /// Runs straight after `importV12Entities`.
    func importV13AndV14Entities() throws {
        let viewContext = context
        let index = self.index

        // v13+ entities
        if let memberships = try rows(\.classroomMemberships) {
            BackupEntityImporter.importRows(
                memberships, as: CDClassroomMembership.self, into: viewContext,
                existing: { try index.existing(CDClassroomMembership.self, id: $0) }
            )
        }

        // v14+ entities
        if let meetingWorkReviews = try rows(\.meetingWorkReviews) {
            BackupEntityImporter.importRows(
                meetingWorkReviews, as: CDMeetingWorkReview.self, into: viewContext,
                existing: { try index.existing(CDMeetingWorkReview.self, id: $0) },
                parents: ["meeting": { viewContext.object(CDStudentMeeting.self, id: $0) }]
            )
        }

        if let studentFocusItems = try rows(\.studentFocusItems) {
            BackupEntityImporter.importRows(
                studentFocusItems, as: CDStudentFocusItem.self, into: viewContext,
                existing: { try index.existing(CDStudentFocusItem.self, id: $0) }
            )
        }
    }

    /// v18+ entities: Stories, Book Club, Year Plan, Lesson Sequence Settings, Day Pads.
    /// Book Club is imported packet -> session -> meeting so meetings can re-wire
    /// their `session` relationship against sessions already in the context.
    func importV18Entities() throws {
        let viewContext = context
        let index = self.index

        if let dayPads = try rows(\.dayPads) {
            BackupEntityImporter.importRows(
                dayPads, as: CDDayPad.self, into: viewContext,
                existing: { try index.existing(CDDayPad.self, id: $0) }
            )
        }

        if let yearPlanEntries = try rows(\.yearPlanEntries) {
            BackupEntityImporter.importRows(
                yearPlanEntries, as: CDYearPlanEntry.self, into: viewContext,
                existing: { try index.existing(CDYearPlanEntry.self, id: $0) }
            )
        }

        if let sequenceSettings = try rows(\.lessonSequenceSettings) {
            BackupEntityImporter.importRows(
                sequenceSettings, as: CDLessonSequenceSettings.self, into: viewContext,
                existing: { try index.existing(CDLessonSequenceSettings.self, id: $0) }
            )
        }

        if let stories = try rows(\.stories) {
            try BackupEntityImporter.importStories(
                stories,
                into: viewContext,
                existing: { try index.existing(CDStory.self, id: $0) }
            )
        }

        if let packets = try rows(\.bookClubPackets) {
            try BackupEntityImporter.importBookClubPackets(
                packets,
                into: viewContext,
                existing: { try index.existing(CDBookClubPacket.self, id: $0) }
            )
        }

        if let sessions = try rows(\.bookClubSessions) {
            BackupEntityImporter.importRows(
                sessions, as: CDBookClubSession.self, into: viewContext,
                existing: { try index.existing(CDBookClubSession.self, id: $0) }
            )
        }

        if let meetings = try rows(\.bookClubMeetings) {
            BackupEntityImporter.importRows(
                meetings, as: CDBookClubMeeting.self, into: viewContext,
                existing: { try index.existing(CDBookClubMeeting.self, id: $0) },
                parents: ["session": { try index.related(CDBookClubSession.self, id: $0) }]
            )
        }
    }

    /// v20+ entities: Guardians and Parent Communications.
    func importV20Entities() throws {
        let viewContext = context
        let index = self.index

        if let guardians = try rows(\.guardians) {
            BackupEntityImporter.importRows(
                guardians, as: CDGuardian.self, into: viewContext,
                existing: { try index.existing(CDGuardian.self, id: $0) }
            )
        }

        if let parentCommunications = try rows(\.parentCommunications) {
            BackupEntityImporter.importRows(
                parentCommunications, as: CDParentCommunication.self, into: viewContext,
                existing: { try index.existing(CDParentCommunication.self, id: $0) }
            )
        }
    }

    /// v21+ entities: teaching-album annotations. Every kind but recent visits
    /// also names its album for the reattach warning.
    func importV21Entities() throws {
        let viewContext = context
        let index = self.index

        if let bookmarks = try rows(\.albumBookmarks) {
            albumIDs.formUnion(bookmarks.compactMap { $0.string("albumID") })
            BackupEntityImporter.importRows(
                bookmarks, as: CDAlbumBookmark.self, into: viewContext,
                existing: { try index.existing(CDAlbumBookmark.self, id: $0) }
            )
        }

        if let notes = try rows(\.albumPageNotes) {
            albumIDs.formUnion(notes.compactMap { $0.string("albumID") })
            BackupEntityImporter.importRows(
                notes, as: CDAlbumPageNote.self, into: viewContext,
                existing: { try index.existing(CDAlbumPageNote.self, id: $0) }
            )
        }

        if let visits = try rows(\.albumRecentVisits) {
            BackupEntityImporter.importRows(
                visits, as: CDAlbumRecentVisit.self, into: viewContext,
                existing: { try index.existing(CDAlbumRecentVisit.self, id: $0) }
            )
        }

        if let positions = try rows(\.albumReadingPositions) {
            albumIDs.formUnion(positions.compactMap { $0.string("albumID") })
            BackupEntityImporter.importRows(
                positions, as: CDAlbumReadingPosition.self, into: viewContext,
                existing: { try index.existing(CDAlbumReadingPosition.self, id: $0) }
            )
        }

        if let highlights = try rows(\.albumHighlights) {
            albumIDs.formUnion(highlights.map(\.albumID))
            BackupEntityImporter.importAlbumHighlights(
                highlights,
                into: viewContext,
                existing: { try index.existing(CDAlbumHighlight.self, id: $0) }
            )
        }

        if let ink = try rows(\.albumPageInk) {
            albumIDs.formUnion(ink.map(\.albumID))
            BackupEntityImporter.importAlbumPageInk(
                ink,
                into: viewContext,
                existing: { try index.existing(CDAlbumPageInk.self, id: $0) }
            )
        }
    }

    /// v27+ entities: Orders.
    func importV27Entities() throws {
        let viewContext = context
        let index = self.index

        if let orderItems = try rows(\.orderItems) {
            BackupEntityImporter.importRows(
                orderItems, as: CDOrderItem.self, into: viewContext,
                existing: { try index.existing(CDOrderItem.self, id: $0) }
            )
        }
    }
}
