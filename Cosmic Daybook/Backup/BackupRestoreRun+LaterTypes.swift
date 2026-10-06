// BackupRestoreRun+LaterTypes.swift
// The restore order, last part: the format v12–v14 types, then v18 (stories,
// book club, year plan, day pads), v20 (guardians, parent communications), v21
// (teaching-album annotations), v27 (orders), v30, v31, v34 and v38 (names).

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

        // v13+ entities: ClassroomMembership rows are carried but never
        // restored (`BackupEntityRegistry.keptOnRestoreEntityNames`). Taking
        // them still frees them in type order like every other type.
        _ = try rows(\.classroomMemberships)

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

    /// v30+ entities: locked attendance days.
    func importV30Entities() throws {
        let viewContext = context
        let index = self.index

        if let locks = try rows(\.attendanceDayLocks) {
            BackupEntityImporter.importRows(
                locks, as: CDAttendanceDayLock.self, into: viewContext,
                existing: { try index.existing(CDAttendanceDayLock.self, id: $0) }
            )
        }
    }

    /// v31+ entities: supply transactions, after the supplies they belong to.
    /// Linked by `supplyID` only, never through `supply`: filing a restored
    /// line into the classroom share would carry a linked staple along, and a
    /// staple already in the share must never be shared again (2026-09-27;
    /// the 2026-10-05 sync and sharing hunt, #5).
    func importV31Entities() throws {
        let viewContext = context
        let index = self.index

        if let transactions = try rows(\.supplyTransactions) {
            BackupEntityImporter.importRows(
                transactions, as: CDSupplyTransaction.self, into: viewContext,
                existing: { try index.existing(CDSupplyTransaction.self, id: $0) }
            )
        }
    }

    /// v34+ entities: front-desk attendance emails and their settings.
    func importV34Entities() throws {
        let viewContext = context
        let index = self.index

        if let sends = try rows(\.attendanceEmailSends) {
            BackupEntityImporter.importRows(
                sends, as: CDAttendanceEmailSend.self, into: viewContext,
                existing: { try index.existing(CDAttendanceEmailSend.self, id: $0) }
            )
        }
        if let settings = try rows(\.attendanceEmailSettings) {
            BackupEntityImporter.importRows(
                settings, as: CDAttendanceEmailSettings.self, into: viewContext,
                existing: { try index.existing(CDAttendanceEmailSettings.self, id: $0) }
            )
        }
    }

    /// v38+ entities: the names people set for themselves. Matched on `id`
    /// like every row. A row restored beside one their other device wrote
    /// since is folded by the owner (`ClassroomNames.foldMyRows`); a copy of
    /// the same row (same `id`, as when CloudKit brings back the original) is
    /// kept, never folded, and reads take the newest. A row the store already
    /// holds with a newer `modifiedAt` (a rename since the backup) is left as
    /// it is: a Merge restore must not put an old name back over a new one,
    /// which would then go to every device as the newest.
    func importV38Entities() throws {
        let viewContext = context
        let index = self.index

        if let people = try rows(\.classroomPeople) {
            let renamedSince = Self.rowsOlderThanStored(people) { try index.existing(CDClassroomPerson.self, id: $0) }
            BackupEntityImporter.importRows(
                people.filter { !renamedSince.contains($0.id) }, as: CDClassroomPerson.self, into: viewContext,
                existing: { try index.existing(CDClassroomPerson.self, id: $0) }
            )
        }
    }

    /// The ids of `rows` whose record the store already holds with a newer
    /// `modifiedAt` than the row's (or the row has none). Only a Merge restore
    /// finds any: a Replace has cleared the store first.
    static func rowsOlderThanStored(
        _ rows: [ClassroomPersonDTO],
        existing: (UUID) throws -> CDClassroomPerson?
    ) -> Set<UUID> {
        var older = Set<UUID>()
        for row in rows {
            guard let stored = try? existing(row.id), let storedAt = stored.modifiedAt else { continue }
            let restoredAt: Date? = if case .date(let date) = row.values["modifiedAt"] { date } else { nil }
            if restoredAt.map({ storedAt > $0 }) ?? true { older.insert(row.id) }
        }
        return older
    }
}
