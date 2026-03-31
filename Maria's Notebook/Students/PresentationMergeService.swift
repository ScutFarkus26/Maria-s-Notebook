import Foundation
import OSLog
import CoreData

@MainActor
enum PresentationMergeService {
    private static let logger = Logger.students

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

        context.delete(source)
        context.safeSave()
        PresentationDetailUtilities.notifyInboxRefresh()
        toastService.showSuccess("Presentations merged")
        return true
    }

    private static func fetchLessonAssignment(id: UUID, context: NSManagedObjectContext) -> CDLessonAssignment? {
        var desc = { let r = NSFetchRequest<CDLessonAssignment>(entityName: "CDLessonAssignment"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); r.fetchLimit = 0; return r }()
        desc.fetchLimit = 1
        do {
            return try context.fetch(desc).first
        } catch {
            logger.warning("Failed to fetch LessonAssignment: \(error)")
            return nil
        }
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
