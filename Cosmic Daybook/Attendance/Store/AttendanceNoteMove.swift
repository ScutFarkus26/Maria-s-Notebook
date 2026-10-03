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
nonisolated enum AttendanceNoteMove {

    /// Moves every linked Note onto its record and returns how many moved.
    /// Never saves.
    @discardableResult
    static func run(using context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "attendanceRecordID != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        var moved = 0
        for note in context.safeFetch(request) where !note.isDeleted {
            guard let recordID = note.attendanceRecordID.flatMap(UUID.init(uuidString:)),
                  let record = context.object(CDAttendanceRecord.self, id: recordID) else { continue }
            record.note = merged(record.note, note.body)
            context.delete(note)
            moved += 1
        }
        return moved
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
