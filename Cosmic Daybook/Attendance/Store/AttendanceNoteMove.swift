import Foundation
import CoreData

/// Moves attendance notes written as private `Note`s onto their shared
/// `AttendanceRecord`.
///
/// Until schema 8 the attendance screen's note was a private Note linked by
/// `attendanceRecordID`, which an assistant's device can never see. The note now
/// lives on the record itself (`CDAttendanceRecord.note`). Each launch carries
/// any linked Note over and deletes it — including one an older build on
/// another device writes before it updates — so the pass stays until every
/// device runs schema 8. A Note whose record is gone is left alone.
///
/// Only a note that is text alone moves (2026-10-05). Those notes came from the
/// general note editor, so some carry a photo, a link to a work, lesson or
/// meeting, several children, or a follow-up or report flag; the record's note
/// holds only words, and moving one of those deleted the rest. They stay
/// Notes, listed under Notes and marked Attendance.
nonisolated enum AttendanceNoteMove {

    /// Moves every linked Note that is text alone onto its record and returns
    /// how many moved. Never saves.
    @discardableResult
    static func run(using context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "attendanceRecordID != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        var moved = 0
        for note in context.safeFetch(request) where !note.isDeleted && isTextAlone(note) {
            guard let recordID = note.attendanceRecordID.flatMap(UUID.init(uuidString:)),
                  let record = context.object(CDAttendanceRecord.self, id: recordID) else { continue }
            record.note = merged(record.note, note.body)
            context.delete(note)
            moved += 1
        }
        return moved
    }

    /// Whether the record's text can hold everything the note says: no photo,
    /// no link to anything but its attendance record, no other children, no
    /// flag. Tags don't count (the old attendance field tagged its notes).
    static func isTextAlone(_ note: CDNote) -> Bool {
        if !(note.imagePath ?? "").isEmpty { return false }
        if note.needsFollowUp || note.includeInReport || note.isPinned { return false }
        if (note.studentLinks?.count ?? 0) > 0 { return false }
        let links: [NSManagedObject?] = [
            note.work, note.lessonAssignment, note.workCheckIn, note.workCompletionRecord,
            note.studentMeeting, note.projectSession, note.reminder, note.practiceSession, note.issue
        ]
        if links.contains(where: { $0 != nil }) { return false }
        let foreignKeys = [
            note.lessonID, note.communityTopicID, note.schoolDayOverrideID,
            note.studentTrackEnrollmentID, note.goingOutID
        ]
        return foreignKeys.allSatisfy { ($0 ?? "").isEmpty }
    }

    /// Two notes for the same child and day as one, dropping a repeat rather
    /// than doubling it.
    static func merged(_ first: String?, _ second: String?) -> String? {
        let kept = first?.trimmed() ?? ""
        let added = second?.trimmed() ?? ""
        if kept.isEmpty { return added.isEmpty ? nil : added }
        if added.isEmpty || kept.contains(added) { return kept }
        return kept + "\n" + added
    }
}
