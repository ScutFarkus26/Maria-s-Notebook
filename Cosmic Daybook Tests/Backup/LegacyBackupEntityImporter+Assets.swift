// swiftlint:disable file_length
import CoreData
import Foundation
import OSLog
@testable import CosmicDaybook

// The last of the old restores (`LegacyBackupEntityImporter.swift`): a906650c0's
// `Backup/Import/BackupEntityImporter+Schedule.swift` (with
// `notifySchoolDayDataChanged`), `+Assets` (Document, Supply, Procedure),
// `+Albums`, `+NewEntities`, `+Resources` and `+V18Entities`, copied verbatim;
// only the names are changed. Do not "fix" or modernise this code: its only
// job is to be the old code.

// MARK: - Backup/Import/BackupEntityImporter+Schedule.swift

// MARK: - Calendar/CDSchedule Imports

extension LegacyBackupEntityImporter {
    private static let logger = Logger.backup

    // MARK: - Non-School Days

    /// Imports non-school days from DTOs.
    static func importNonSchoolDays(
        _ dtos: [LegacyNonSchoolDayDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDNonSchoolDay>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let day = current ?? CDNonSchoolDay(context: viewContext)
            day.id = dto.id
            day.date = dto.date
            day.reason = dto.reason
            return day
        })
        notifySchoolDayDataChanged(ifImported: dtos)
    }

    // MARK: - School Day Overrides

    /// Imports school day overrides from DTOs.
    static func importSchoolDayOverrides(
        _ dtos: [LegacySchoolDayOverrideDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDSchoolDayOverride>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let override = current ?? CDSchoolDayOverride(context: viewContext)
            override.id = dto.id
            override.date = dto.date
            return override
        })
        notifySchoolDayDataChanged(ifImported: dtos)
    }

    /// A restore writes calendar rows through the view context, whose saves are
    /// the app's own and so never reach the history-driven invalidation in
    /// `PersistentHistoryProcessor`. Announce the change here instead.
    private static func notifySchoolDayDataChanged<T>(ifImported dtos: [T]) {
        guard !dtos.isEmpty else { return }
        NotificationCenter.default.post(name: .schoolDayDataDidChange, object: nil)
    }

    // MARK: - CDSchedule Slots

    static func importScheduleSlots(
        _ dtos: [LegacyScheduleSlotDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDScheduleSlot>,
        scheduleCheck: EntityLookup<CDSchedule>
    ) rethrows {
        for dto in dtos {
            let slot = existingEntity(id: dto.id, existing: existing) ?? CDScheduleSlot(context: viewContext)
            slot.id = dto.id
            slot.scheduleID = dto.scheduleID
            slot.studentID = dto.studentID
            slot.weekdayRaw = (Weekday(rawValue: dto.weekdayRaw) ?? .monday).rawValue
            slot.timeString = dto.timeString
            slot.sortOrder = Int64(dto.sortOrder)
            slot.notes = dto.notes
            slot.createdAt = dto.createdAt
            slot.modifiedAt = dto.modifiedAt
            if let scheduleUUID = UUID(uuidString: dto.scheduleID) {
                do {
                    if let schedule = try scheduleCheck(scheduleUUID) {
                        slot.schedule = schedule
                    }
                } catch {
                    let desc = error.localizedDescription
                    Self.logger.warning("Failed to check schedule for slot: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(slot)
        }
    }
}

// MARK: - Backup/Import/BackupEntityImporter+Assets.swift

// MARK: - CDDocument/CDSupply/CDProcedure Imports

extension LegacyBackupEntityImporter {

    // MARK: - Documents

    static func importDocuments(
        _ dtos: [LegacyDocumentDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDDocument>
    ) rethrows {
        for dto in dtos {
            let d = existingEntity(id: dto.id, existing: existing) ?? CDDocument(context: viewContext)
            d.id = dto.id
            d.title = dto.title
            d.category = dto.category
            d.uploadDate = dto.uploadDate
            // document → student is a cross-store string FK, not a Core Data
            // relationship. Restore the raw ID unconditionally: requiring the
            // student to already be resolvable here silently dropped the link
            // (the computed `student` accessor tolerates a dangling ID).
            d.studentID = dto.studentID?.uuidString
            d.pdfFileRelativePath = dto.pdfFileRelativePath ?? ""
            viewContext.insert(d)
        }
    }

    // MARK: - Supplies

    static func importSupplies(
        _ dtos: [LegacySupplyDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDSupply>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let s = current ?? CDSupply(context: viewContext)
            s.id = dto.id
            s.name = dto.name
            s.categoryRaw = (SupplyCategory(rawValue: dto.categoryRaw) ?? .other).rawValue
            s.location = dto.location
            s.currentQuantity = Int64(dto.currentQuantity)
            s.notes = dto.notes
            s.createdAt = dto.createdAt
            s.modifiedAt = dto.modifiedAt
            // Restock (v37+). An older row has none of these: a new staple keeps
            // the defaults, and one already here keeps what it has.
            if let threshold = dto.minimumThreshold { s.minimumThreshold = Int64(threshold) }
            if let unit = dto.unit { s.unit = unit }
            if let level = dto.levelRaw { s.level = RestockLevel(rawValue: level) ?? .stocked }
            if let source = dto.sourceRaw { s.source = RestockSource(rawValue: source) ?? .office }
            if let link = dto.urlString { s.urlString = link }
            if dto.levelRaw != nil {
                s.levelChangedAt = dto.levelChangedAt
                s.levelChangedByID = dto.levelChangedByID
                s.levelChangedByName = dto.levelChangedByName ?? ""
            }
            return s
        })
    }

    // MARK: - Procedures

    static func importProcedures(
        _ dtos: [LegacyProcedureDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDProcedure>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let p = current ?? CDProcedure(context: viewContext)
            p.id = dto.id
            p.title = dto.title
            p.summary = dto.summary
            p.content = dto.content
            p.categoryRaw = (ProcedureCategory(rawValue: dto.categoryRaw) ?? .other).rawValue
            p.icon = dto.icon
            p.relatedProcedureIDs = dto.relatedProcedureIDs
            p.createdAt = dto.createdAt
            p.modifiedAt = dto.modifiedAt
            return p
        })
    }
}

// MARK: - Backup/Import/BackupEntityImporter+Albums.swift

// MARK: - Teaching-album annotation importers (format v21+)

extension LegacyBackupEntityImporter {

    // MARK: - CDAlbumHighlight

    static func importAlbumHighlights(
        _ dtos: [LegacyAlbumHighlightDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDAlbumHighlight>
    ) {
        for dto in dtos {
            let entity = existingEntity(id: dto.id, existing: existing) ?? CDAlbumHighlight(context: viewContext)
            entity.id = dto.id
            entity.albumID = dto.albumID
            entity.pageIndex = Int32(dto.pageIndex)
            entity.lessonTitle = dto.lessonTitle
            entity.text = dto.text
            entity.colorName = dto.colorName
            entity.setRectValues(dto.rects)
            entity.createdAt = dto.createdAt
            entity.modifiedAt = dto.modifiedAt
        }
    }

    // MARK: - CDAlbumPageInk

    static func importAlbumPageInk(
        _ dtos: [LegacyAlbumPageInkDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDAlbumPageInk>
    ) {
        for dto in dtos {
            let entity = existingEntity(id: dto.id, existing: existing) ?? CDAlbumPageInk(context: viewContext)
            entity.id = dto.id
            entity.albumID = dto.albumID
            entity.pageIndex = Int32(dto.pageIndex)
            entity.drawingData = dto.drawingData.isEmpty ? nil : dto.drawingData
            entity.modifiedAt = dto.modifiedAt
        }
    }
}

// MARK: - Backup/Import/BackupEntityImporter+NewEntities.swift

// MARK: - CDGoingOut, CDCalendarNote, CDScheduledMeeting

extension LegacyBackupEntityImporter {

    // MARK: - CDGoingOutChecklistItem

    static func importGoingOutChecklistItems(
        _ dtos: [LegacyGoingOutChecklistItemDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDGoingOutChecklistItem>,
        goingOutCheck: EntityLookup<CDGoingOut>
    ) rethrows {
        for dto in dtos {
            guard let goingOutUUID = UUID(uuidString: dto.goingOutID) else { continue }
            let item = existingEntity(id: dto.id, existing: existing) ?? CDGoingOutChecklistItem(context: viewContext)
            item.id = dto.id
            item.goingOutID = goingOutUUID.uuidString
            item.title = dto.title
            item.isCompleted = dto.isCompleted
            item.sortOrder = Int64(dto.sortOrder)
            item.assignedToStudentID = dto.assignedToStudentID
            item.createdAt = dto.createdAt
            do {
                if let goingOut = try goingOutCheck(goingOutUUID) {
                    item.goingOut = goingOut
                }
            } catch {
                Logger.backup.warning(
                    "Failed to check goingOut for checklist item: \(error.localizedDescription, privacy: .public)"
                )
            }
            viewContext.insert(item)
        }
    }

    // MARK: - CDScheduledMeeting

    static func importScheduledMeetings(
        _ dtos: [LegacyScheduledMeetingDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDScheduledMeeting>
    ) rethrows {
        for dto in dtos {
            guard let studentUUID = UUID(uuidString: dto.studentID) else { continue }
            let meeting = existingEntity(id: dto.id, existing: existing) ?? CDScheduledMeeting(context: viewContext)
            meeting.id = dto.id
            meeting.studentID = studentUUID.uuidString
            meeting.date = dto.date
            meeting.createdAt = dto.createdAt
            meeting._participantIDsData = dto.participantIDsData
            meeting.workID = dto.workID
            meeting.isGroupMeeting = dto.isGroupMeeting ?? false
            meeting.purpose = dto.purpose
            viewContext.insert(meeting)
        }
    }

}

// MARK: - Backup/Import/BackupEntityImporter+Resources.swift

// MARK: - CDResource & CDNoteStudentLink Import

extension LegacyBackupEntityImporter {

    // MARK: - CDResource

    static func importResources(
        _ dtos: [LegacyResourceDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDResource>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
                let r = current ?? CDResource(context: viewContext)
                r.id = dto.id
                r.title = dto.title
                r.descriptionText = dto.descriptionText
                r.categoryRaw = (ResourceCategory(rawValue: dto.categoryRaw) ?? .other).rawValue
                r.fileRelativePath = dto.fileRelativePath
                r.fileSizeBytes = dto.fileSizeBytes
                r.tags = dto.tags as NSArray
                r.isFavorite = dto.isFavorite
                r.linkedLessonIDs = dto.linkedLessonIDs
                r.linkedAreas = dto.linkedAreas
                r.lastViewedAt = dto.lastViewedAt
                r.createdAt = dto.createdAt
                r.modifiedAt = dto.modifiedAt
                return r
            })
    }

}

// MARK: - Backup/Import/BackupEntityImporter+V18Entities.swift

// MARK: - Format v18 Importers
//
// DTO -> CD object importers for the entity types added to backup coverage in
// format v18: CDDayPad, CDYearPlanEntry, CDLessonSequenceSettings, CDStory,
// CDBookClubPacket, CDBookClubSession, CDBookClubMeeting.
//
// Book Club imports are ordered packet -> session -> meeting by the caller so
// that `importBookClubMeetings` can re-wire each meeting's `session`
// relationship (the inverse of `BookClubSession.meetings`).

extension LegacyBackupEntityImporter {

    // MARK: - CDStory

    static func importStories(
        _ dtos: [LegacyStoryDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDStory>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let story = current ?? CDStory(context: viewContext)
            story.id = dto.id
            story.title = dto.title
            story.summary = dto.summary
            story.gradeMinRaw = dto.gradeMinRaw
            story.gradeMaxRaw = dto.gradeMaxRaw
            story.themesArray = dto.themes
            story.pdfFileRelativePath = dto.pdfFileRelativePath
            story.pageCount = Int32(dto.pageCount)
            story.createdAt = dto.createdAt
            story.modifiedAt = dto.modifiedAt
            story.analysisStatusRaw = dto.analysisStatusRaw
            story.analysisErrorMessage = dto.analysisErrorMessage
            story.analysisModelVersion = dto.analysisModelVersion
            story.extractedTextHash = dto.extractedTextHash
            story.userEditedTitle = dto.userEditedTitle
            story.userEditedThemes = dto.userEditedThemes
            story.relatedLessonIDsRaw = dto.relatedLessonIDsRaw
            story.relatedLessonReasonsJSON = dto.relatedLessonReasonsJSON
            story.relatedLessonsAnalyzedAt = dto.relatedLessonsAnalyzedAt
            // pdfFileBookmark / thumbnailData / generatedCoverData not backed up.
            return story
        })
    }

    // MARK: - CDBookClubPacket

    static func importBookClubPackets(
        _ dtos: [LegacyBookClubPacketDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDBookClubPacket>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let packet = current ?? CDBookClubPacket(context: viewContext)
            packet.id = dto.id
            packet.title = dto.title
            packet.author = dto.author
            packet.gradeMinRaw = dto.gradeMinRaw
            packet.gradeMaxRaw = dto.gradeMaxRaw
            packet.themesArray = dto.themes
            packet.teachingNotes = dto.teachingNotes
            packet.packetPDFRelativePath = dto.packetPDFRelativePath
            packet.pageCount = Int32(dto.pageCount)
            packet.readingItemsJSON = dto.readingItemsJSON
            packet.createdAt = dto.createdAt
            packet.modifiedAt = dto.modifiedAt
            // packetPDFBookmark / thumbnailData not backed up.
            return packet
        })
    }

}
