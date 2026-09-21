import Foundation
import CoreData
import CloudKit
import os

// MARK: - Deduplicate Work & Projects

nonisolated extension DataCleanupService {

    // swiftlint:disable cyclomatic_complexity
    @discardableResult
    static func deduplicateWorkModelsStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> Int {
        deduplicate(CDWorkModel.self, using: context, container: container, scope: scope) { canonical, duplicate in
            mergeWorkModel(canonical: canonical, duplicate: duplicate, context: context)
        }
    }

    private static func mergeWorkModel(
        canonical: CDWorkModel,
        duplicate: CDWorkModel,
        context: NSManagedObjectContext
    ) {
        if canonical.title.isEmpty { canonical.title = duplicate.title }
        let dupNoteText = duplicate.latestUnifiedNoteText.trimmed()
        if canonical.latestUnifiedNoteText.trimmed().isEmpty && !dupNoteText.isEmpty {
            canonical.setLegacyNoteText(dupNoteText, in: context)
        }
        if canonical.completedAt == nil { canonical.completedAt = duplicate.completedAt }
        if canonical.lastTouchedAt == nil { canonical.lastTouchedAt = duplicate.lastTouchedAt }
        if canonical.dueAt == nil { canonical.dueAt = duplicate.dueAt }
        if canonical.completionOutcomeRaw == nil { canonical.completionOutcomeRaw = duplicate.completionOutcomeRaw }
        if canonical.studentID.isEmpty { canonical.studentID = duplicate.studentID }
        if canonical.lessonID.isEmpty { canonical.lessonID = duplicate.lessonID }
        if canonical.presentationID == nil { canonical.presentationID = duplicate.presentationID }
        if canonical.trackID == nil { canonical.trackID = duplicate.trackID }
        if canonical.trackStepID == nil { canonical.trackStepID = duplicate.trackStepID }
        if canonical.scheduledNote == nil { canonical.scheduledNote = duplicate.scheduledNote }
        if canonical.scheduledReasonRaw == nil { canonical.scheduledReasonRaw = duplicate.scheduledReasonRaw }
        if canonical.sourceContextTypeRaw == nil { canonical.sourceContextTypeRaw = duplicate.sourceContextTypeRaw }
        if canonical.sourceContextID == nil { canonical.sourceContextID = duplicate.sourceContextID }

        let rawParticipants = canonical.participants as? Set<CDWorkParticipantEntity>
        var existingParticipantIDs = Set(rawParticipants?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.participants,
            addTo: canonical,
            relationshipKey: "participants",
            existingIDs: &existingParticipantIDs,
            setter: { (p: CDWorkParticipantEntity) in p.work = canonical }
        )

        var existingCheckInIDs = Set((canonical.checkIns as? Set<CDWorkCheckIn>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.checkIns,
            addTo: canonical,
            relationshipKey: "checkIns",
            existingIDs: &existingCheckInIDs,
            setter: { (ci: CDWorkCheckIn) in ci.work = canonical; ci.workID = (canonical.id ?? UUID()).uuidString }
        )

        var existingStepIDs = Set((canonical.steps as? Set<CDWorkStep>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.steps,
            addTo: canonical,
            relationshipKey: "steps",
            existingIDs: &existingStepIDs,
            setter: { (step: CDWorkStep) in step.work = canonical }
        )

        var existingNoteIDs = Set((canonical.unifiedNotes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.unifiedNotes,
            addTo: canonical,
            relationshipKey: "unifiedNotes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.work = canonical }
        )
    }

    static func mergeWorkCheckIn(canonical: CDWorkCheckIn, duplicate: CDWorkCheckIn) {
        var existingNoteIDs = Set((canonical.notes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.notes,
            addTo: canonical,
            relationshipKey: "notes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.workCheckIn = canonical }
        )
    }

    static func mergeWorkCompletionRecord(canonical: CDWorkCompletionRecord, duplicate: CDWorkCompletionRecord) {
        var existingNoteIDs = Set((canonical.notes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.notes,
            addTo: canonical,
            relationshipKey: "notes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.workCompletionRecord = canonical }
        )
    }

    static func mergeProjectSession(canonical: CDProjectSession, duplicate: CDProjectSession) {
        var existingNoteIDs = Set((canonical.noteItems as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.noteItems,
            addTo: canonical,
            relationshipKey: "noteItems",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.projectSession = canonical }
        )
    }
}
// swiftlint:enable cyclomatic_complexity
