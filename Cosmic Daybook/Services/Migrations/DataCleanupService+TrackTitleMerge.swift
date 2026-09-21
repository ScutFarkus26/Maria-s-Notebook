//
//  DataCleanupService+TrackTitleMerge.swift
//  Cosmic Daybook
//
//  Folding sequence tracks that were defined twice under one title.
//
//  The id-based pass in +Deduplication catches CloudKit's own duplicates —
//  two rows, one UUID. This pass catches the shape a twice-run migration
//  left on Danny's store (2026-01-10): two `CDTrackEntity` rows, two UUIDs,
//  the same "Area — Sequence" title. `getOrCreateTrack` picked whichever
//  twin an unsorted fetch returned first, so a child's enrollments spread
//  across both, one twin often carried the steps and the other sat empty,
//  and `student_tracks` printed both.
//
//  The older record survives, by the same evidence `mergeSameNameLessons`
//  uses so every synced device keeps the same copy: the CloudKit record's
//  creation date when it has been exported, then `createdAt`, then the
//  record name and object URI. Steps move to the survivor (a step for a
//  lesson it already has is dropped, and everything that named the dropped
//  step is repointed at the kept one), enrollments move and a child left
//  with two keeps one, and the id strings on presentations, marks and work
//  follow. `SequenceTrackService.preferredTrack` keeps the runtime lookup
//  deterministic so a twin cannot grow back before the next pass.
//

import CloudKit
import CoreData
import Foundation
import OSLog

nonisolated extension DataCleanupService {

    /// Tracks that share one title, keyed case- and whitespace-insensitively.
    static func sameTitleTrackGroups(using context: NSManagedObjectContext) -> [[CDTrackEntity]] {
        // Cheap pre-check on the title column alone; see `sameNameLessonGroups`.
        let request = CDFetchRequest(CDTrackEntity.self)
        if let collidingIDs = sameTitleTrackObjectIDs(in: context) {
            if collidingIDs.isEmpty { return [] }
            request.predicate = NSPredicate(format: "SELF IN %@", collidingIDs)
        }
        let tracks = context.safeFetch(request).filter { !$0.isDeleted }
        let grouped = Dictionary(grouping: tracks, by: trackTitleKey)
        return grouped.values.filter { $0.count > 1 }
            .sorted { lhs, rhs in trackTitleKey(lhs[0]) < trackTitleKey(rhs[0]) }
    }

    static func trackTitleKey(_ track: CDTrackEntity) -> String {
        track.title.folded()
    }

    /// Object IDs of every track whose folded title repeats, read from the
    /// title column alone. `nil` when the context has pending changes.
    private static func sameTitleTrackObjectIDs(in context: NSManagedObjectContext) -> [NSManagedObjectID]? {
        guard !context.hasChanges, let entityName = CDFetchRequest(CDTrackEntity.self).entityName else { return nil }

        let objectIDColumn = NSExpressionDescription()
        objectIDColumn.name = "objectID"
        objectIDColumn.expression = NSExpression.expressionForEvaluatedObject()
        objectIDColumn.expressionResultType = .objectIDAttributeType

        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [objectIDColumn, "title"]

        let rows: [NSDictionary]
        do {
            rows = try context.fetch(request)
        } catch {
            return nil
        }

        var byKey: [String: [NSManagedObjectID]] = [:]
        for row in rows {
            guard let objectID = row["objectID"] as? NSManagedObjectID else { continue }
            byKey[(row["title"] as? String ?? "").folded(), default: []].append(objectID)
        }
        return byKey.values.filter { $0.count > 1 }.flatMap { $0 }
    }

    /// Folds every same-title group down to its oldest record and returns
    /// how many duplicates were removed. Never saves; the caller batches.
    @discardableResult
    static func mergeSameTitleTracks(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil
    ) -> Int {
        let groups = sameTitleTrackGroups(using: context)
        guard !groups.isEmpty else { return 0 }

        var removed: Int = 0
        for group in groups {
            let ordered: [CDTrackEntity] = group.sorted { (lhs: CDTrackEntity, rhs: CDTrackEntity) -> Bool in
                olderTrackPrecedes(lhs, rhs, container: container)
            }
            guard let canonical: CDTrackEntity = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                let summary: String = "\"\(duplicate.title)\" \(duplicate.id?.uuidString ?? "?") "
                    + "into \(canonical.id?.uuidString ?? "?")"
                merge(duplicateTrack: duplicate, into: canonical, in: context)
                removed += 1
                logger.info("Folded duplicate track \(summary, privacy: .public)")
            }
        }
        return removed
    }

    // MARK: - Survivor Ordering

    /// Whether `lhs` is the older of two same-title tracks, by evidence every
    /// synced device sees the same way. Step counts are deliberately not
    /// consulted: the merge moves the steps, so which twin keeps them does
    /// not matter, and only creation order converges across peers.
    static func olderTrackPrecedes(
        _ lhs: CDTrackEntity, _ rhs: CDTrackEntity, container: NSPersistentCloudKitContainer?
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

        let lhsLocal = lhs.createdAt ?? .distantFuture
        let rhsLocal = rhs.createdAt ?? .distantFuture
        if lhsLocal != rhsLocal { return lhsLocal < rhsLocal }

        let lhsName = container?.recordID(for: lhs.objectID)?.recordName
        let rhsName = container?.recordID(for: rhs.objectID)?.recordName
        if let lhsName, let rhsName, lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.objectID.uriRepresentation().absoluteString
            < rhs.objectID.uriRepresentation().absoluteString
    }

    // MARK: - Merge

    /// Moves everything that names `duplicate` onto `canonical` and deletes
    /// the duplicate.
    static func merge(
        duplicateTrack duplicate: CDTrackEntity, into canonical: CDTrackEntity, in context: NSManagedObjectContext
    ) {
        guard duplicate !== canonical, !duplicate.isDeleted else { return }

        mergeSequenceTrack(from: duplicate, into: canonical, in: context)
        let stepRemap = mergeSteps(from: duplicate, into: canonical, in: context)
        mergeEnrollments(from: duplicate, into: canonical, in: context)

        if let oldID = duplicate.id?.uuidString, let newID = canonical.id?.uuidString {
            repointTrackReferences(from: oldID, to: newID, steps: stepRemap, in: context)
        }
        context.delete(duplicate)
    }

    /// The survivor takes the sequence-track link if it has none; a second
    /// sequence-track row for the same area and sequence goes with the twin.
    private static func mergeSequenceTrack(
        from duplicate: CDTrackEntity, into canonical: CDTrackEntity, in context: NSManagedObjectContext
    ) {
        guard let extra = duplicate.sequenceTrack else { return }
        guard let kept = canonical.sequenceTrack else {
            canonical.sequenceTrack = extra
            return
        }
        guard extra !== kept else { return }
        if extra.sequenceKey.caseInsensitiveCompare(kept.sequenceKey) == .orderedSame {
            if extra.isExplicitlyDisabled { kept.isExplicitlyDisabled = true }
            context.delete(extra)
        }
    }

    /// Steps move to the survivor. A duplicate step for a lesson the survivor
    /// already steps through is deleted, and its id is returned mapped to
    /// the kept step's so the records that named it can follow.
    private static func mergeSteps(
        from duplicate: CDTrackEntity, into canonical: CDTrackEntity, in context: NSManagedObjectContext
    ) -> [String: String] {
        let keptSteps = (canonical.steps?.allObjects as? [CDTrackStepEntity]) ?? []
        var keptByLesson: [UUID: CDTrackStepEntity] = [:]
        for step in keptSteps {
            if let lessonID = step.lessonTemplateID, keptByLesson[lessonID] == nil { keptByLesson[lessonID] = step }
        }

        var remap: [String: String] = [:]
        let moving = ((duplicate.steps?.allObjects as? [CDTrackStepEntity]) ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
        for step in moving {
            if let lessonID = step.lessonTemplateID, let kept = keptByLesson[lessonID] {
                if let oldID = step.id?.uuidString, let newID = kept.id?.uuidString { remap[oldID] = newID }
                context.delete(step)
            } else {
                step.track = canonical
                if let lessonID = step.lessonTemplateID { keptByLesson[lessonID] = step }
            }
        }
        return remap
    }

    /// Enrollments move to the survivor, and a child then enrolled twice
    /// keeps one: active over inactive, then the earlier start.
    private static func mergeEnrollments(
        from duplicate: CDTrackEntity, into canonical: CDTrackEntity, in context: NSManagedObjectContext
    ) {
        guard let oldID = duplicate.id?.uuidString, let newID = canonical.id?.uuidString else { return }
        let byRelationship = (duplicate.enrollments?.allObjects as? [CDStudentTrackEnrollmentEntity]) ?? []
        let byString = fetch(CDStudentTrackEnrollmentEntity.self, where: "trackID == %@", oldID, in: context)
        for enrollment in Set(byRelationship + byString) {
            enrollment.trackID = newID
            enrollment.track = canonical
        }

        let all = fetch(CDStudentTrackEnrollmentEntity.self, where: "trackID == %@", newID, in: context)
        let byChild = Dictionary(grouping: all, by: \.studentID)
        for enrollments in byChild.values where enrollments.count > 1 {
            let ordered = enrollments.sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                let lhsStart = lhs.startedAt ?? lhs.createdAt ?? .distantFuture
                let rhsStart = rhs.startedAt ?? rhs.createdAt ?? .distantFuture
                if lhsStart != rhsStart { return lhsStart < rhsStart }
                return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
            }
            guard let keeper = ordered.first, let keeperID = keeper.id?.uuidString else { continue }
            for extra in ordered.dropFirst() {
                if let extraID = extra.id?.uuidString {
                    for note in fetch(CDNote.self, where: "studentTrackEnrollmentID == %@", extraID, in: context) {
                        note.studentTrackEnrollmentID = keeperID
                    }
                }
                context.delete(extra)
            }
        }
    }

    /// Every record that keys a track or step by its id string.
    private static func repointTrackReferences(
        from oldID: String, to newID: String, steps remap: [String: String], in context: NSManagedObjectContext
    ) {
        for assignment in fetch(CDLessonAssignment.self, where: "trackID == %@", oldID, in: context) {
            assignment.trackID = newID
            if let stepID = assignment.trackStepID, let kept = remap[stepID] { assignment.trackStepID = kept }
        }
        for mark in fetch(CDLessonPresentation.self, where: "trackID == %@", oldID, in: context) {
            mark.trackID = newID
            if let stepID = mark.trackStepID, let kept = remap[stepID] { mark.trackStepID = kept }
        }
        for work in fetch(CDWorkModel.self, where: "trackID == %@", oldID, in: context) {
            work.trackID = newID
            if let stepID = work.trackStepID, let kept = remap[stepID] { work.trackStepID = kept }
        }
        // A step id can travel without its track id; catch those too.
        for (oldStep, newStep) in remap {
            for assignment in fetch(CDLessonAssignment.self, where: "trackStepID == %@", oldStep, in: context) {
                assignment.trackStepID = newStep
            }
            for mark in fetch(CDLessonPresentation.self, where: "trackStepID == %@", oldStep, in: context) {
                mark.trackStepID = newStep
            }
            for work in fetch(CDWorkModel.self, where: "trackStepID == %@", oldStep, in: context) {
                work.trackStepID = newStep
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
}
