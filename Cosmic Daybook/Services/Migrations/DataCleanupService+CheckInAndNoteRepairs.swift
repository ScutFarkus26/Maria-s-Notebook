//
//  DataCleanupService+CheckInAndNoteRepairs.swift
//  Cosmic Daybook
//
//  Two launch-time repairs for records that read wrong over MCP on
//  2026-09-09, each cheap enough to run on every launch.
//
//  Work check-ins. Five creation paths wrote `workID` as a string and never
//  set the `work` relationship, so a reader that followed the relationship
//  saw "Untitled work — unassigned" for a check-in whose work was right
//  there. Those are relinked. A check-in whose `workID` names no work at
//  all outlived its work — a bare `context.delete(work)` cascades only the
//  relationship — and is deleted, but not on the first run on a device: a
//  fresh install may still be receiving its work rows from CloudKit, and a
//  check-in that arrives a batch ahead of its work is not an orphan.
//
//  Presentation notes. A note written on a presentation with no child
//  selected was saved with the whole-class scope, so an observation about
//  one girl counted as an observation of every child on the roster. Such a
//  note is narrowed to the children who received the presentation, which
//  is the widest thing it can truthfully be about. `UnifiedNoteEditor` no
//  longer writes that shape.
//

import CoreData
import Foundation
import OSLog

nonisolated extension DataCleanupService {

    struct CheckInRepairReport: Equatable {
        var relinked = 0
        var orphansDeleted = 0
        var orphansKept = 0
    }

    /// Restores the `work` relationship on check-ins that carry only the
    /// `workID` string, and removes the ones whose work no longer exists
    /// (only when `deleteOrphans` is true). Never saves.
    @discardableResult
    static func repairWorkCheckInLinks(
        using context: NSManagedObjectContext, deleteOrphans: Bool
    ) -> CheckInRepairReport {
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = NSPredicate(format: "work == nil")
        let unlinked = context.safeFetch(request).filter { !$0.isDeleted }
        guard !unlinked.isEmpty else { return CheckInRepairReport() }

        var report = CheckInRepairReport()
        var worksByID: [String: CDWorkModel] = [:]
        for checkIn in unlinked {
            let key = checkIn.workID.uppercased()
            let work: CDWorkModel?
            if let cached = worksByID[key] {
                work = cached
            } else if let id = UUID(uuidString: checkIn.workID), let found = context.object(CDWorkModel.self, id: id) {
                worksByID[key] = found
                work = found
            } else {
                work = nil
            }

            if let work {
                checkIn.work = work
                report.relinked += 1
            } else if deleteOrphans {
                context.delete(checkIn)
                report.orphansDeleted += 1
            } else {
                report.orphansKept += 1
            }
        }

        let summary: String = "relinked \(report.relinked), deleted \(report.orphansDeleted) orphan(s), "
            + "kept \(report.orphansKept)"
        logger.info("Check-in repair: \(summary, privacy: .public)")
        return report
    }

    /// Narrows presentation-linked notes saved with the whole-class scope to
    /// the presentation's own children. Returns how many notes changed.
    /// Never saves.
    @discardableResult
    static func repairPresentationNoteScopes(using context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "lessonAssignment != nil AND scopeIsAll == YES")
        var changed = 0
        for note in context.safeFetch(request) where !note.isDeleted {
            guard case .all = note.scope, let presentation = note.lessonAssignment else { continue }
            let roster = presentation.studentUUIDs
            guard !roster.isEmpty else { continue }
            note.scope = NoteScope.forSelection([], fallback: roster)
            note.syncStudentLinks(in: context)
            changed += 1
        }
        if changed > 0 {
            logger.info("Narrowed \(changed, privacy: .public) whole-class presentation note(s) to their roster")
        }
        return changed
    }
}
