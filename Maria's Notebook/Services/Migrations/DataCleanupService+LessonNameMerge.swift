//
//  DataCleanupService+LessonNameMerge.swift
//  Maria's Notebook
//
//  Folding lessons that were filed twice under one name in one sub-area.
//
//  The id-based pass in +Deduplication catches CloudKit's own duplicates —
//  two rows, one UUID. This pass catches the other shape: two rows, two
//  UUIDs, the same name in the same sub-area. That is what a sub-area
//  entered twice through the Bulk Entry sheet left in Geometry › Area on
//  Danny's store (2026-09-09): Rectangle, Parallelogram and the three
//  triangles twice each, and every child's year plan doubled with them.
//
//  The older record survives. Lessons carry no createdAt, so "older" is
//  read from what every device sees identically: the CloudKit record's
//  creation date when the record has been exported, then the position in
//  the sub-area (appending is what re-entry does, so the first-entered copy
//  sits earlier), then the record name and object URI as tie-breaks. Every
//  peer therefore keeps the same copy, which the id-based pass already
//  relies on: two devices keeping opposite copies would each delete the
//  other's and both deletes would sync.
//
//  Everything that points at the duplicate by id string is repointed at the
//  survivor — presentations, mastery marks, year-plan entries, work,
//  notes, recall checks, planning recommendations, resources, stories,
//  track steps, and the lesson-to-lesson links — and the year-plan entries
//  and marks a child now holds twice for one lesson are folded to one.
//  `LessonRepository.createLesson` refuses the same name in the same
//  sub-area, so this should find nothing to do after the first run.
//

import CloudKit
import CoreData
import Foundation
import OSLog

nonisolated extension DataCleanupService {

    /// Lessons that share one name in one sub-area, keyed by the repository's
    /// folded name key. Parsha lessons are left out: they repeat their names
    /// by design, one per week.
    static func sameNameLessonGroups(using context: NSManagedObjectContext) -> [[CDLesson]] {
        let lessons = context.safeFetch(CDFetchRequest(CDLesson.self))
            .filter { !$0.isDeleted && LessonRepository.participatesInNameUniqueness($0) }
        let grouped = Dictionary(grouping: lessons, by: LessonRepository.nameKey(for:))
        return grouped.values.filter { $0.count > 1 }
            .sorted { lhs, rhs in
                LessonRepository.nameKey(for: lhs[0]) < LessonRepository.nameKey(for: rhs[0])
            }
    }

    /// Folds every same-name group down to its oldest record and returns
    /// how many duplicates were removed. Never saves; the caller batches.
    @discardableResult
    static func mergeSameNameLessons(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil
    ) -> Int {
        let groups = sameNameLessonGroups(using: context)
        guard !groups.isEmpty else { return 0 }

        var removed: Int = 0
        for group in groups {
            let ordered: [CDLesson] = group.sorted { (lhs: CDLesson, rhs: CDLesson) -> Bool in
                olderLessonPrecedes(lhs, rhs, container: container)
            }
            guard let canonical: CDLesson = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                let summary: String = "\"\(duplicate.name)\" in \(duplicate.area) › \(duplicate.sequence) "
                    + "into \(canonical.id?.uuidString ?? "?")"
                merge(duplicate: duplicate, into: canonical, in: context)
                removed += 1
                logger.info("Folded duplicate lesson \(summary, privacy: .public)")
            }
        }
        return removed
    }

    // MARK: - Survivor Ordering

    /// Whether `lhs` is the older of two same-name lessons, by evidence every
    /// synced device sees the same way. See the file comment.
    static func olderLessonPrecedes(
        _ lhs: CDLesson, _ rhs: CDLesson, container: NSPersistentCloudKitContainer?
    ) -> Bool {
        let lhsCreated = container?.record(for: lhs.objectID)?.creationDate
        let rhsCreated = container?.record(for: rhs.objectID)?.creationDate
        switch (lhsCreated, rhsCreated) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        if lhs.orderInSequence != rhs.orderInSequence {
            return lhs.orderInSequence < rhs.orderInSequence
        }
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }

        let lhsName = container?.recordID(for: lhs.objectID)?.recordName
        let rhsName = container?.recordID(for: rhs.objectID)?.recordName
        if let lhsName, let rhsName, lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.objectID.uriRepresentation().absoluteString
            < rhs.objectID.uriRepresentation().absoluteString
    }

    // MARK: - Merge

    /// Moves everything that names `duplicate` onto `canonical`, fills the
    /// survivor's empty fields from the duplicate, and deletes the duplicate.
    static func merge(duplicate: CDLesson, into canonical: CDLesson, in context: NSManagedObjectContext) {
        guard duplicate !== canonical, !duplicate.isDeleted else { return }
        mergeLesson(canonical: canonical, duplicate: duplicate)
        if !canonical.isKeyLesson, duplicate.isKeyLesson { canonical.isKeyLesson = true }
        if (canonical.albumID ?? "").isEmpty, let albumID = duplicate.albumID, !albumID.isEmpty {
            canonical.albumID = albumID
            canonical.albumPageIndex = duplicate.albumPageIndex
            canonical.albumLessonTitle = duplicate.albumLessonTitle
            canonical.albumLinkConfidence = duplicate.albumLinkConfidence
        }
        for field: ReferenceWritableKeyPath<CDLesson, String> in [
            \.materials, \.purpose, \.ageRange, \.teacherNotes, \.suggestedFollowUpWork
        ] where canonical[keyPath: field].trimmed().isEmpty {
            canonical[keyPath: field] = duplicate[keyPath: field]
        }

        for attachment in (duplicate.attachments?.allObjects as? [CDLessonAttachment]) ?? [] {
            attachment.lesson = canonical
        }
        for sampleWork in (duplicate.sampleWorks?.allObjects as? [CDSampleWorkEntity]) ?? [] {
            sampleWork.lesson = canonical
        }

        if let duplicateID = duplicate.id, let canonicalID = canonical.id {
            repointLessonReferences(from: duplicateID, to: canonicalID, in: context)
        }
        context.delete(duplicate)
    }

    /// Every record that keys a lesson by its id string, moved from `old` to `new`.
    static func repointLessonReferences(from old: UUID, to new: UUID, in context: NSManagedObjectContext) {
        let oldID = old.uuidString
        let newID = new.uuidString

        for assignment in fetch(CDLessonAssignment.self, where: "lessonID == %@", oldID, in: context) {
            assignment.lessonID = newID
        }
        for work in fetch(CDWorkModel.self, where: "lessonID == %@", oldID, in: context) {
            work.lessonID = newID
        }
        for check in fetch(CDLessonRecallCheck.self, where: "lessonID == %@", oldID, in: context) {
            check.lessonID = newID
        }
        for check in fetch(CDLessonRecallCheck.self, where: "coveredByLessonID == %@", oldID, in: context) {
            check.coveredByLessonID = newID
        }
        for recommendation in fetch(CDPlanningRecommendation.self, where: "lessonID == %@", oldID, in: context) {
            recommendation.lessonID = newID
        }
        repointLessonLinks(from: oldID, to: newID, in: context)
        repointTrackSteps(from: old, to: new, in: context)
        repointMarks(from: oldID, to: newID, in: context)
        repointYearPlanEntries(from: oldID, to: newID, in: context)
    }

    /// The lesson-to-lesson, resource and story links, which hold ids singly
    /// or as comma-separated lists.
    private static func repointLessonLinks(from oldID: String, to newID: String, in context: NSManagedObjectContext) {
        for lesson in fetch(CDLesson.self, where: "derivedFromLessonID == %@", oldID, in: context) {
            lesson.derivedFromLessonID = newID
        }
        for lesson in fetch(CDLesson.self, where: "parentStoryID == %@", oldID, in: context) {
            lesson.parentStoryID = newID
        }
        for lesson in fetch(CDLesson.self, where: "prerequisiteLessonIDs CONTAINS %@", oldID, in: context) {
            lesson.prerequisiteLessonIDs = replacing(oldID, with: newID, inList: lesson.prerequisiteLessonIDs)
        }
        for lesson in fetch(CDLesson.self, where: "relatedLessonIDs CONTAINS %@", oldID, in: context) {
            lesson.relatedLessonIDs = replacing(oldID, with: newID, inList: lesson.relatedLessonIDs)
        }
        for resource in fetch(CDResource.self, where: "linkedLessonIDs CONTAINS %@", oldID, in: context) {
            resource.linkedLessonIDs = replacing(oldID, with: newID, inList: resource.linkedLessonIDs)
        }
        for story in fetch(CDStory.self, where: "relatedLessonIDsRaw CONTAINS %@", oldID, in: context) {
            story.relatedLessonIDsRaw = replacing(oldID, with: newID, inList: story.relatedLessonIDsRaw)
        }
    }

    // MARK: - Per-child collapses

    /// Mastery and presentation marks (`CDLessonPresentation`) move to the
    /// survivor. A child who then holds two marks for one lesson from the same
    /// presentation keeps the earlier one, carrying forward any mastery or
    /// observation date the later one recorded.
    private static func repointMarks(from oldID: String, to newID: String, in context: NSManagedObjectContext) {
        let moved = fetch(CDLessonPresentation.self, where: "lessonID == %@", oldID, in: context)
        guard !moved.isEmpty else { return }
        for mark in moved { mark.lessonID = newID }

        let all = fetch(CDLessonPresentation.self, where: "lessonID == %@", newID, in: context)
        let byChild = Dictionary(grouping: all) { "\($0.studentID)|\($0.presentationID ?? "")" }
        for marks in byChild.values where marks.count > 1 {
            let ordered = marks.sorted { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
            guard let keeper = ordered.first else { continue }
            for extra in ordered.dropFirst() {
                if keeper.presentedAt == nil { keeper.presentedAt = extra.presentedAt }
                if keeper.masteredAt == nil { keeper.masteredAt = extra.masteredAt }
                if keeper.lastObservedAt == nil { keeper.lastObservedAt = extra.lastObservedAt }
                if (keeper.notes ?? "").trimmed().isEmpty { keeper.notes = extra.notes }
                context.delete(extra)
            }
        }
    }

    /// Year-plan entries move to the survivor, and a child left with two
    /// entries for one lesson keeps one: a promoted entry (a presentation was
    /// scheduled from it) over a planned one, and planned over skipped — a
    /// guide who noticed the double and skipped one copy meant the other.
    private static func repointYearPlanEntries(
        from oldID: String, to newID: String, in context: NSManagedObjectContext
    ) {
        let moved = fetch(CDYearPlanEntry.self, where: "lessonID == %@", oldID, in: context)
        guard !moved.isEmpty else { return }
        for entry in moved { entry.lessonID = newID }

        let all = fetch(CDYearPlanEntry.self, where: "lessonID == %@", newID, in: context)
        let byChild = Dictionary(grouping: all, by: \.studentID)
        for entries in byChild.values where entries.count > 1 {
            let ordered = entries.sorted { lhs, rhs in
                let lhsRank = yearPlanKeepRank(lhs.status)
                let rhsRank = yearPlanKeepRank(rhs.status)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
            }
            for extra in ordered.dropFirst() {
                context.delete(extra)
            }
        }
    }

    private static func yearPlanKeepRank(_ status: YearPlanEntryStatus) -> Int {
        switch status {
        case .promoted: return 0
        case .planned: return 1
        case .skipped: return 2
        }
    }

    /// A track that stepped through both copies keeps one step for the lesson.
    private static func repointTrackSteps(from old: UUID, to new: UUID, in context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDTrackStepEntity.self)
        request.predicate = NSPredicate(format: "lessonTemplateID == %@", old as CVarArg)
        let moved = context.safeFetch(request)
        guard !moved.isEmpty else { return }

        let existing = CDFetchRequest(CDTrackStepEntity.self)
        existing.predicate = NSPredicate(format: "lessonTemplateID == %@", new as CVarArg)
        let tracksAlreadyStepping = Set(context.safeFetch(existing).compactMap { $0.track?.objectID })

        for step in moved {
            if let trackID = step.track?.objectID, tracksAlreadyStepping.contains(trackID) {
                context.delete(step)
            } else {
                step.lessonTemplateID = new
            }
        }
    }

    // MARK: - Helpers

    private static func fetch<T: NSManagedObject>(
        _ type: T.Type, where format: String, _ argument: String, in context: NSManagedObjectContext
    ) -> [T] {
        let request = CDFetchRequest(T.self)
        request.predicate = NSPredicate(format: format, argument)
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    /// Rewrites one id in a comma-separated id list, dropping the double that
    /// results when both ids were already listed.
    private static func replacing(_ old: String, with new: String, inList list: String) -> String {
        var seen: Set<String> = []
        var kept: [String] = []
        for piece in list.split(separator: ",") {
            let trimmed: String = String(piece).trimmed()
            if trimmed.isEmpty { continue }
            let isOld: Bool = trimmed.caseInsensitiveCompare(old) == .orderedSame
            let id: String = isOld ? new : trimmed
            if seen.insert(id.uppercased()).inserted { kept.append(id) }
        }
        return kept.joined(separator: ",")
    }
}
