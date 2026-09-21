import Foundation
import CoreData
import CloudKit
import os

// MARK: - Deduplicate Lessons & Presentations

nonisolated extension DataCleanupService {

    // swiftlint:disable cyclomatic_complexity
    /// Deduplicate draft CDLessonAssignment records that refer to the same lesson and identical student set.
    /// Keeps the earliest `createdAt` as canonical, merges flags, and deletes the rest.
    static func deduplicateDraftLessonAssignments(using context: NSManagedObjectContext) {
        let draftRaw = LessonAssignmentState.draft.rawValue
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "stateRaw == %@", draftRaw)
        let candidates = context.safeFetch(request)
        guard !candidates.isEmpty else { return }

        // Group by (lessonID + sorted studentIDs)
        let groups = candidates.grouped { la -> String in
            let sortedIDs = la.studentIDs.sorted()
            return la.lessonID + "|" + sortedIDs.joined(separator: ",")
        }

        var changed = false
        for (_, sequence) in groups {
            guard sequence.count > 1 else { continue }
            guard let canonical = sequence.sorted(by: { lhs, rhs in
                let lhsDate = lhs.createdAt ?? Date.distantPast
                let rhsDate = rhs.createdAt ?? Date.distantPast
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return (lhs.id ?? UUID()).uuidString < (rhs.id ?? UUID()).uuidString
            }).first else { continue }
            let duplicates = sequence.filter { $0.id != canonical.id }

            if duplicates.contains(where: { $0.needsPractice }) {
                canonical.needsPractice = true
            }
            if duplicates.contains(where: { $0.needsAnotherPresentation }) {
                canonical.needsAnotherPresentation = true
            }
            if canonical.notes.trimmed().isEmpty {
                if let firstNote = duplicates.map({ $0.notes }).first(where: { !$0.trimmed().isEmpty }) {
                    canonical.notes = firstNote
                }
            }
            if canonical.followUpWork.trimmed().isEmpty {
                if let firstFU = duplicates.map({ $0.followUpWork }).first(where: { !$0.trimmed().isEmpty }) {
                    canonical.followUpWork = firstFU
                }
            }

            for d in duplicates {
                // Re-parent the duplicate's notes onto the survivor first —
                // unifiedNotes is a Cascade relationship, so a raw delete would
                // destroy any observation notes attached to the duplicate draft.
                mergeLessonAssignment(canonical: canonical, duplicate: d)
                context.delete(d)
            }
            changed = true
        }

        if changed { context.safeSave() }
    }

    @discardableResult
    static func deduplicateLessonsStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> Int {
        deduplicate(CDLesson.self, using: context, container: container, scope: scope, merge: mergeLesson)
    }

    @discardableResult
    static func deduplicateLessonPresentationsStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> Int {
        deduplicate(
            CDLessonPresentation.self, using: context, container: container, scope: scope,
            merge: mergeLessonPresentation
        )
    }

    static func mergeLesson(canonical: CDLesson, duplicate: CDLesson) {
        if canonical.name.isEmpty { canonical.name = duplicate.name }
        if canonical.area.isEmpty { canonical.area = duplicate.area }
        if canonical.sequence.isEmpty { canonical.sequence = duplicate.sequence }
        if canonical.section.isEmpty { canonical.section = duplicate.section }
        if canonical.writeUp.isEmpty { canonical.writeUp = duplicate.writeUp }
        if canonical.orderInSequence == 0 && duplicate.orderInSequence != 0 {
            canonical.orderInSequence = duplicate.orderInSequence
        }
        if canonical.sortIndex == 0 && duplicate.sortIndex != 0 { canonical.sortIndex = duplicate.sortIndex }
        if canonical.pagesFileBookmark == nil { canonical.pagesFileBookmark = duplicate.pagesFileBookmark }
        if canonical.pagesFileRelativePath == nil { canonical.pagesFileRelativePath = duplicate.pagesFileRelativePath }
        if canonical.personalKindRaw == nil { canonical.personalKindRaw = duplicate.personalKindRaw }
        if canonical.defaultWorkKindRaw == nil { canonical.defaultWorkKindRaw = duplicate.defaultWorkKindRaw }

        // Re-point duplicate lesson's notes to canonical via FK
        if let dupID = duplicate.id?.uuidString, let ctx = canonical.managedObjectContext {
            let noteReq = CDFetchRequest(CDNote.self)
            noteReq.predicate = NSPredicate(format: "lessonID == %@", dupID)
            for note in (try? ctx.fetch(noteReq)) ?? [] {
                note.lesson = canonical
            }

            // Re-point duplicate lesson's assignments to canonical via FK
            let laReq = CDFetchRequest(CDLessonAssignment.self)
            laReq.predicate = NSPredicate(format: "lessonID == %@", dupID)
            for la in (try? ctx.fetch(laReq)) ?? [] {
                la.lesson = canonical
            }
        }
    }

    private static func mergeLessonPresentation(canonical: CDLessonPresentation, duplicate: CDLessonPresentation) {
        if canonical.studentID.isEmpty { canonical.studentID = duplicate.studentID }
        if canonical.lessonID.isEmpty { canonical.lessonID = duplicate.lessonID }
        if canonical.presentationID == nil { canonical.presentationID = duplicate.presentationID }
        if canonical.trackID == nil { canonical.trackID = duplicate.trackID }
        if canonical.trackStepID == nil { canonical.trackStepID = duplicate.trackStepID }
        if canonical.lastObservedAt == nil { canonical.lastObservedAt = duplicate.lastObservedAt }
        if canonical.masteredAt == nil { canonical.masteredAt = duplicate.masteredAt }
        if (canonical.notes ?? "").isEmpty { canonical.notes = duplicate.notes }

        // Follow-up is one conflict-resolution bundle. Mixing an older action with
        // a newer resolution can accidentally reopen a responsibility on another
        // shared device, so copy every field from whichever bundle was updated last.
        let canonicalFollowUpDate = canonical.followUpUpdatedAt ?? .distantPast
        let duplicateFollowUpDate = duplicate.followUpUpdatedAt ?? .distantPast
        if duplicateFollowUpDate > canonicalFollowUpDate
            || (canonical.followUpActionRaw == nil && duplicate.followUpActionRaw != nil) {
            canonical.followUpActionRaw = duplicate.followUpActionRaw
            canonical.followUpReviewAt = duplicate.followUpReviewAt
            canonical.followUpResolvedAt = duplicate.followUpResolvedAt
            canonical.followUpResolutionRaw = duplicate.followUpResolutionRaw
            canonical.followUpUpdatedAt = duplicate.followUpUpdatedAt
            canonical.followUpEvidenceRaw = duplicate.followUpEvidenceRaw
            canonical.followUpNote = duplicate.followUpNote
            canonical.followUpSupportRaw = duplicate.followUpSupportRaw
        }
    }

    static func mergeLessonAssignment(canonical: CDLessonAssignment, duplicate: CDLessonAssignment) {
        var existingNoteIDs = Set((canonical.unifiedNotes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.unifiedNotes,
            addTo: canonical,
            relationshipKey: "unifiedNotes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.lessonAssignment = canonical }
        )
    }
}
// swiftlint:enable cyclomatic_complexity
