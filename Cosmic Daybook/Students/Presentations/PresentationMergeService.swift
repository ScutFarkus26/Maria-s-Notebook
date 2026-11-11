import Foundation
import CoreData

enum PresentationMergeService {
    @discardableResult
    static func merge(
        sourceID: UUID, targetID: UUID,
        context: NSManagedObjectContext,
        toastService: ToastService = ToastService.shared
    ) -> Bool {
        guard sourceID != targetID else { return false }

        guard let source = fetchLessonAssignment(id: sourceID, context: context),
              let target = fetchLessonAssignment(id: targetID, context: context) else {
            toastService.showInfo("Couldn't find those presentations.")
            return false
        }

        guard !source.isGiven, !target.isGiven else {
            toastService.showInfo("Only planned presentations can be merged.")
            return false
        }

        guard source.resolvedLessonID == target.resolvedLessonID else {
            toastService.showInfo("Only presentations for the same lesson can be merged.")
            return false
        }

        let mergedStudentIDs = mergeStudentIDs(
            targetIDs: target.studentIDs,
            sourceIDs: source.studentIDs
        )
        target.studentIDs = mergedStudentIDs
        target.updateDenormalizedKeys()

        target.needsPractice = target.needsPractice || source.needsPractice
        target.needsAnotherPresentation = target.needsAnotherPresentation || source.needsAnotherPresentation
        target.notes = mergeText(target.notes, source.notes)
        target.followUpWork = mergeText(target.followUpWork, source.followUpWork)
        carrySetTime(from: source, to: target)
        target.modifiedAt = Date()

        // The source's observation notes cascade with it, and year-plan
        // entries promoted into it would point at nothing: both move to the
        // target first.
        PresentationRecordCleanup.prepareToMerge(source, into: target, in: context)
        context.delete(source)
        context.safeSave()
        PresentationDetailUtilities.notifyInboxRefresh()
        toastService.showSuccess("Presentations merged")
        return true
    }

    /// A set time stays with the lesson (plan "Lesson times on cards",
    /// decision 5): merging a timed card into one without a time gives the
    /// merged card that time, on the merged card's own day. A target that
    /// already has a time keeps its own.
    static func carrySetTime(
        from source: CDLessonAssignment,
        to target: CDLessonAssignment,
        using calendar: Calendar = AppCalendar.shared
    ) {
        guard let targetDate = target.scheduledFor,
              !DayHalfPlanner.isSetTime(targetDate, using: calendar),
              let kept = DayHalfPlanner.keptTime(of: source.scheduledFor, using: calendar) else { return }
        target.schedule(for: DayHalfPlanner.rebasing(kept, onto: targetDate, using: calendar), using: calendar)
    }

    private static func fetchLessonAssignment(id: UUID, context: NSManagedObjectContext) -> CDLessonAssignment? {
        context.object(CDLessonAssignment.self, id: id)
    }

    private static func mergeStudentIDs(targetIDs: [String], sourceIDs: [String]) -> [String] {
        var merged = targetIDs
        var seen = Set(targetIDs)
        for sid in sourceIDs where !seen.contains(sid) {
            merged.append(sid)
            seen.insert(sid)
        }
        return merged
    }

    private static func mergeText(_ target: String, _ source: String) -> String {
        let trimmedTarget = target.trimmed()
        let trimmedSource = source.trimmed()
        if trimmedTarget.isEmpty { return source }
        if trimmedSource.isEmpty { return target }
        if trimmedTarget == trimmedSource { return target }
        return "\(trimmedTarget)\n\(trimmedSource)"
    }
}
