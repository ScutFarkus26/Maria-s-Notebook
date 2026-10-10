// RecallService.swift
// The write side of the Lesson Recall feature: records a recall outcome for a frontier lesson
// and runs the consequences — WITHOUT ever mutating the mastery record except a narrow
// lastObservedAt bump on a retained outcome.
//
//   retained  → bump CDLessonPresentation.lastObservedAt (only) + stamp covered lower lessons
//   shaky     → set needsPractice on the matching assignment(s) she was given alone; when she
//               had it with a group, practice work of her own on her latest giving instead,
//               since the group's flag held every child in it back
//   forgotten → set needsAnotherPresentation on the matching assignment(s)
//
// `masteredAt`/`stateRaw` on CDLessonPresentation are never touched — that's the "never
// overwrite the ladder" guarantee (do NOT route through updateProficiencyState, which nulls
// masteredAt on non-proficient transitions).

import Foundation
import CoreData
import OSLog

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
        let request = CDFetchRequest(CDLessonPresentation.self)
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
        let request = CDFetchRequest(CDLessonRecallCheck.self)
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
    /// fallout shows up wherever those flags are already read.
    ///
    /// `needsPractice` is a whole presentation's flag, and the blocking check holds back every
    /// child on it who has no work of her own. So it is set only where she was given the lesson
    /// alone; when she had it with a group she gets practice work of her own on her latest
    /// giving instead, which gates her and nobody else.
    private func setFollowUp(entry: RecallQueueEntry, needsPractice: Bool, needsAnotherPresentation: Bool) {
        let request = CDFetchRequest(CDLessonAssignment.self)
        // Predicate on lessonID (stored as String) to avoid a full-table scan.
        request.predicate = NSPredicate(format: "lessonID == %@", entry.frontierLessonID.uuidString)
        let sid = RecallFrontierEngine.normalize(entry.studentID)
        let hers = context.safeFetch(request).filter { assignment in
            assignment.studentIDs.contains(where: { RecallFrontierEngine.normalize($0) == sid })
        }
        var flaggedHerOwn = false
        for assignment in hers {
            let alone = Set(assignment.studentIDs.map(RecallFrontierEngine.normalize)) == [sid]
            if needsAnotherPresentation { assignment.needsAnotherPresentation = true }
            if needsPractice && alone {
                assignment.needsPractice = true
                flaggedHerOwn = true
            }
            if needsAnotherPresentation || (needsPractice && alone) { assignment.modifiedAt = Date() }
        }
        if needsPractice, !flaggedHerOwn,
           let latest = BlockingAlgorithmEngine.latestFirst(hers.filter(\.isGiven)).first {
            addPracticeWork(studentID: sid, lessonID: entry.frontierLessonID, on: latest)
        }
    }

    /// Practice work of her own on `presentation`, unless she already has open work there.
    private func addPracticeWork(studentID: String, lessonID: UUID, on presentation: CDLessonAssignment) {
        guard let studentUUID = UUID(uuidString: studentID), let presentationID = presentation.id else { return }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "presentationID == %@", presentationID.uuidString),
            WorkStatus.openPredicate
        ])
        let hasOpenWork = context.safeFetch(request).contains { work in
            WorkGrouping.owner(of: work) == studentUUID
        }
        guard !hasOpenWork else { return }
        do {
            try WorkRepository(context: context).createWork(
                studentID: studentUUID,
                lessonID: lessonID,
                kind: .practiceLesson,
                presentationID: presentationID,
                saveImmediately: false
            )
        } catch {
            Logger.students.warning("Recall: no practice work added for a shaky check: \(error.localizedDescription)")
        }
    }
}
