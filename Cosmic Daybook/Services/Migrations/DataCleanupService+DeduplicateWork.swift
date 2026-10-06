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

    /// The duplicate's notes move below, which carries their text; writing it
    /// again as a new note first (`setLegacyNoteText`) left two (#39). The
    /// retired `completionOutcomeRaw` isn't copied: on a row the guide has
    /// since marked Done it folded the status back to the old verdict (#8).
    private static func mergeWorkModel(
        canonical: CDWorkModel,
        duplicate: CDWorkModel,
        context: NSManagedObjectContext
    ) {
        if canonical.title.isEmpty { canonical.title = duplicate.title }
        if canonical.completedAt == nil { canonical.completedAt = duplicate.completedAt }
        if canonical.lastTouchedAt == nil { canonical.lastTouchedAt = duplicate.lastTouchedAt }
        if canonical.dueAt == nil { canonical.dueAt = duplicate.dueAt }
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

        linkIDOnlyCheckIns(to: canonical, in: context)
    }

    /// Check-ins that name the work by its id string alone, which older
    /// creation paths wrote without the relationship, are given it, on the
    /// copy kept (#11). The id is both copies', so these belong to the kept one
    /// as much as to the duplicate; `CDWorkModel.prepareForDeletion` also
    /// leaves them alone while a copy with the id remains.
    private static func linkIDOnlyCheckIns(to canonical: CDWorkModel, in context: NSManagedObjectContext) {
        guard let workID = canonical.id?.uuidString else { return }
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = NSPredicate(format: "workID == %@ AND work == nil", workID)
        for checkIn in context.safeFetch(request) where !checkIn.isDeleted {
            checkIn.work = canonical
        }
    }

    /// Sessions name their project by id too, but the relationship is what the
    /// project's screens read, and it only nullifies when the copy holding
    /// them is deleted (#12).
    static func mergeProject(canonical: CDProject, duplicate: CDProject) {
        var existingSessionIDs = Set((canonical.sessions as? Set<CDProjectSession>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.sessions,
            addTo: canonical,
            relationshipKey: "sessions",
            existingIDs: &existingSessionIDs,
            setter: { (session: CDProjectSession) in session.project = canonical }
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

    /// A practice session owns its notes through a Cascade rule, so the
    /// duplicate's notes move onto the survivor before the duplicate is deleted.
    static func mergePracticeSession(canonical: CDPracticeSession, duplicate: CDPracticeSession) {
        var existingNoteIDs = Set((canonical.notes as? Set<CDNote>)?.compactMap(\.id) ?? [])
        mergeNSSetRelationship(
            from: duplicate.notes,
            addTo: canonical,
            relationshipKey: "notes",
            existingIDs: &existingNoteIDs,
            setter: { (note: CDNote) in note.practiceSession = canonical }
        )
    }
}
// swiftlint:enable cyclomatic_complexity
