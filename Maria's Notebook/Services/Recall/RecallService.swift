// RecallService.swift
// The write side of the Lesson Recall feature: records a recall outcome for a frontier lesson
// and runs the consequences — WITHOUT ever mutating the mastery record except a narrow
// lastObservedAt bump on a retained outcome.
//
//   retained  → bump CDLessonPresentation.lastObservedAt (only) + stamp covered lower lessons
//   shaky     → set needsPractice on the matching assignment(s)
//   forgotten → set needsAnotherPresentation on the matching assignment(s)
//
// `masteredAt`/`stateRaw` on CDLessonPresentation are never touched — that's the "never
// overwrite the ladder" guarantee (do NOT route through updateProficiencyState, which nulls
// masteredAt on non-proficient transitions).

import Foundation
import CoreData

@MainActor
struct RecallService {
    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator
    let schoolYearStore: SchoolYearStore

    @discardableResult
    func record(entry: RecallQueueEntry, outcome: RecallOutcome, note: String) -> Bool {
        let yearKey = schoolYearStore.current.key
        let now = Date()

        // The observed check for the frontier lesson itself.
        let check = CDLessonRecallCheck(context: context)
        check.studentID = entry.studentID
        check.lessonID = entry.frontierLessonID.uuidString
        check.outcome = outcome
        check.source = .observed
        check.originalMasteredAt = entry.frontierMasteredAt
        check.checkedAt = now
        check.schoolYearKey = yearKey
        check.note = note.isEmpty ? nil : note

        switch outcome {
        case .retained:
            bumpLastObserved(studentID: entry.studentID, lessonID: entry.frontierLessonID, at: now)
            stampCovered(for: entry, yearKey: yearKey, at: now)
        case .shaky:
            setFollowUp(entry: entry, needsPractice: true, needsAnotherPresentation: false)
        case .forgotten:
            setFollowUp(entry: entry, needsPractice: false, needsAnotherPresentation: true)
        }

        return saveCoordinator.save(context, reason: "Recording lesson recall")
    }

    /// Bumps `lastObservedAt` on the matching proficient presentation(s). Never touches
    /// `stateRaw` or `masteredAt` — recall must not overwrite mastery.
    private func bumpLastObserved(studentID: String, lessonID: UUID, at date: Date) {
        let request = NSFetchRequest<CDLessonPresentation>(entityName: "LessonPresentation")
        // Predicate on both lessonID and studentID to avoid fetching the full table.
        // stateRaw filter added so we only load proficient rows.
        request.predicate = NSPredicate(
            format: "lessonID == %@ AND studentID == %@ AND stateRaw == %@",
            lessonID.uuidString,
            studentID,
            LessonPresentationState.proficient.rawValue
        )
        for presentation in context.safeFetch(request) {
            presentation.lastObservedAt = date
        }
    }

    /// Inserts `source == .covered` rows (presumed retained) for the lower lessons a retained
    /// frontier implies, skipping any already recorded this year (idempotent via the engine).
    private func stampCovered(for entry: RecallQueueEntry, yearKey: String, at date: Date) {
        // Scope to this student + year to avoid loading the full recall-check table.
        let request = NSFetchRequest<CDLessonRecallCheck>(entityName: "LessonRecallCheck")
        request.predicate = NSPredicate(
            format: "studentID == %@ AND schoolYearKey == %@",
            entry.studentID, yearKey
        )
        let existing = context.safeFetch(request)
            .map {
                RecallExisting(
                    studentID: $0.studentID, lessonID: $0.lessonID,
                    schoolYearKey: $0.schoolYearKey, source: $0.source, checkedAt: $0.checkedAt
                )
            }
        let intents = RecallFrontierEngine.coveredIntents(forRetained: entry, existing: existing, schoolYearKey: yearKey)
        for intent in intents {
            let covered = CDLessonRecallCheck(context: context)
            covered.studentID = intent.studentID
            covered.lessonID = intent.lessonID
            covered.outcome = .retained
            covered.source = .covered
            covered.coveredByLessonID = intent.coveredByLessonID
            covered.originalMasteredAt = intent.originalMasteredAt
            covered.checkedAt = date
            covered.schoolYearKey = yearKey
        }
    }

    /// Sets the existing follow-up flags on any assignment for this lesson + student, so recall
    /// fallout surfaces in the Follow-up Inbox (FollowUpInboxEngine already reads these flags).
    private func setFollowUp(entry: RecallQueueEntry, needsPractice: Bool, needsAnotherPresentation: Bool) {
        let request = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        // Predicate on lessonID (stored as String) to avoid a full-table scan.
        request.predicate = NSPredicate(format: "lessonID == %@", entry.frontierLessonID.uuidString)
        let sid = RecallFrontierEngine.normalize(entry.studentID)
        for assignment in context.safeFetch(request)
        where assignment.studentIDs.contains(where: { RecallFrontierEngine.normalize($0) == sid }) {
            if needsPractice { assignment.needsPractice = true }
            if needsAnotherPresentation { assignment.needsAnotherPresentation = true }
            assignment.modifiedAt = Date()
        }
    }
}
