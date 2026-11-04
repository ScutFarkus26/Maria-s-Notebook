import Foundation
import CoreData
import os

// MARK: - Presentation Recording

extension LifecycleService {

    /// Record a CDLessonAssignment as presented and upsert CDLessonPresentation records,
    /// but do NOT auto-create CDWorkModel items. Use this when work creation is handled separately
    /// (e.g., via the unified workflow panel or explicit user action).
    ///
    /// Every child the assignment names stays on it. One with no student row here (still on
    /// her way from iCloud, departed, or an id typed by hand) gets no history row until she
    /// is found; taking her off, as this did until 2026-10-05, synced the loss to every
    /// device. Ids compare trimmed and upper-cased, and history rows carry the student's own id.
    static func recordPresentation(
        from lessonAssignment: CDLessonAssignment,
        presentedAt: Date,
        modelContext: NSManagedObjectContext,
        beginFollowUp: Bool = true,
        followExistingRows: Bool = true
    ) throws -> CDLessonAssignment {
        let lessonIDStr = lessonAssignment.lessonID
        let studentIDStrs = try knownStudentIDs(namedBy: lessonAssignment, context: modelContext)

        // A given presentation whose lesson was changed: its history rows move with it.
        relinkHistoryRows(of: lessonAssignment, in: modelContext)
        // Entries promoted into it for the lesson it used to be on go back to planned.
        PresentationRecordCleanup.returnEntriesForOtherLessons(promotedInto: lessonAssignment, in: modelContext)

        // Apply the supplied occurrence date even when this assignment was
        // previously stored as an undated or older presentation. The operation is
        // still idempotent because the per-student rows are upserted below.
        lessonAssignment.markPresented(at: presentedAt)

        // Upsert CDLessonPresentation records per student (for individual progress tracking)
        let assignmentIDStr = lessonAssignment.id?.uuidString ?? ""
        for sid in studentIDStrs {
            let historyRow = try upsertLessonPresentation(
                presentationID: assignmentIDStr,
                studentID: sid,
                lessonID: lessonIDStr,
                presentedAt: presentedAt,
                context: modelContext
            )
            // Recording again follows every child; a Save of a presentation
            // already given (`followExistingRows` false) follows only a child
            // it adds, since the rest were followed, or settled, already.
            if beginFollowUp && (followExistingRows || historyRow.isInserted) {
                PresentationFollowUpService.beginFollowing(historyRow, at: presentedAt)
            }
        }

        // The history rows above are what settle these children's year-plan
        // intentions — that reading is derived, not written (YearPlanSatisfaction).
        // What is not derived is a plan for the same lesson still sitting on
        // another day: take the children who have just had it off that group.
        YearPlanReleaseService.releaseRedundantPlans(after: lessonAssignment, in: modelContext)

        return lessonAssignment
    }

    /// The `uuidString`s of the students `lessonAssignment` names that exist.
    /// Only those students can be valid, so this reads them (by UUID — `id` is
    /// a UUID attribute) rather than the whole roster; an id string that
    /// doesn't parse, or whose student is gone, is absent from the set exactly
    /// as it was from the whole-roster set.
    static func existingStudentIDStrings(
        namedBy lessonAssignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) throws -> Set<String> {
        let named = Array(Set(lessonAssignment.studentIDs.compactMap {
            UUID(uuidString: OrphanStudentGrace.normalizedID($0))
        }))
        guard !named.isEmpty else { return [] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", named)
        return Set(try context.fetch(request).compactMap { $0.id?.uuidString })
    }

    /// The students `lessonAssignment` names that exist, as their own ids
    /// (`uuidString`), in the order it names them, each once. The ids it names
    /// that aren't here are left out, and left on the assignment.
    static func knownStudentIDs(
        namedBy lessonAssignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) throws -> [String] {
        let existing = try existingStudentIDStrings(namedBy: lessonAssignment, context: context)
        var seen = Set<String>()
        return lessonAssignment.studentIDs
            .map(OrphanStudentGrace.normalizedID)
            .filter { existing.contains($0) && seen.insert($0).inserted }
    }
}
