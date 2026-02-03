import Foundation
import SwiftData

@MainActor
enum StudentLessonMergeService {
    @discardableResult
    static func merge(sourceID: UUID, targetID: UUID, context: ModelContext) -> Bool {
        guard sourceID != targetID else { return false }

        guard let source = fetchStudentLesson(id: sourceID, context: context),
              let target = fetchStudentLesson(id: targetID, context: context) else {
            ToastService.shared.showInfo("Couldn't find those presentations.")
            return false
        }

        guard !source.isGiven, !target.isGiven else {
            ToastService.shared.showInfo("Only planned presentations can be merged.")
            return false
        }

        guard source.resolvedLessonID == target.resolvedLessonID else {
            ToastService.shared.showInfo("Only presentations for the same lesson can be merged.")
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
        StudentLessonDetailUtilities.notifyInboxRefresh()
        ToastService.shared.showSuccess("Presentations merged")
        return true
    }

    private static func fetchStudentLesson(id: UUID, context: ModelContext) -> StudentLesson? {
        var desc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        return (try? context.fetch(desc))?.first
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
