// PresentationsViewModel+ChangeInputs.swift
// What `update` reads besides the open work and the assignment table, and the
// hashes it compares to decide whether anything moved: everything the
// readiness engine reads, so a change to any of it redraws Ready and Brewing.

import CoreData
import Foundation

extension PresentationsViewModel {
    /// Computes a hash for CDLessonAssignment change detection
    func computeLessonAssignmentHash(_ assignments: [CDLessonAssignment]) -> Int {
        var hasher = Hasher()
        for la in assignments {
            hasher.combine(la.id)
            hasher.combine(la.scheduledFor?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(la.presentedAt?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(la.stateRaw)
            hasher.combine(la.notes)
            hasher.combine(la.followUpWork)
            // The stored bytes, not the decoded array: the same bytes always
            // decode to the same ids, and hashing them skips a JSON decode per row.
            hasher.combine(la._studentIDsData)
            hasher.combine(la.needsPractice)
            hasher.combine(la.needsAnotherPresentation)
            hasher.combine(la.lessonID)
            hasher.combine(la.manuallyUnblocked)
            // A confirmation readies a child for the next lesson.
            hasher.combine(la._confirmedStudentIDsData)
        }
        return hasher.finalize()
    }

    /// Computes a hash for CDWorkModel change detection: status, presentation
    /// link, and each child's part (a child who finished her part of shared
    /// work is ready; bug hunt 2026-11-03 #6).
    func computeWorkModelHash(_ workModels: [CDWorkModel]) -> Int {
        var hasher = Hasher()
        for w in workModels {
            hasher.combine(w.id)
            hasher.combine(w.statusRaw)
            hasher.combine(w.presentationID)
            let participants = ((w.participants?.allObjects as? [CDWorkParticipantEntity]) ?? [])
                .sorted { $0.studentID < $1.studentID }
            for participant in participants {
                hasher.combine(participant.studentID)
                hasher.combine(participant.completedAt?.timeIntervalSinceReferenceDate ?? -1)
            }
        }
        return hasher.finalize()
    }

    /// Computes a hash for the roster: a withdrawal or a rename (test
    /// students are picked by name) changes who the backlog shows.
    func computeStudentsHash(_ students: [CDStudent]) -> Int {
        var hasher = Hasher()
        for student in students {
            hasher.combine(student.id)
            hasher.combine(student.enrollmentStatusRaw)
            hasher.combine(student.firstName)
            hasher.combine(student.lastName)
        }
        return hasher.finalize()
    }

    /// The screen's own settings: a change to one re-sorts or re-filters the
    /// backlog with nothing in the store moved.
    static func settingsHash(
        _ inboxOrderRaw: String,
        _ showTestStudents: Bool,
        _ testStudentNamesRaw: String
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(inboxOrderRaw)
        hasher.combine(showTestStudents)
        hasher.combine(testStudentNamesRaw)
        return hasher.finalize()
    }

    /// What the readiness engine reads off each lesson: its place in a
    /// sequence and both rule overrides. Hashing ids alone left Ready and
    /// Brewing as they were after a lesson's rules, area, sequence or position
    /// changed (bug hunt 2026-11-03 #6).
    static func lessonsHash(_ lessons: [CDLesson]) -> Int {
        var hasher = Hasher()
        for lesson in lessons {
            hasher.combine(lesson.id)
            hasher.combine(lesson.area)
            hasher.combine(lesson.sequence)
            hasher.combine(lesson.orderInSequence)
            hasher.combine(lesson.requiresPracticeOverride)
            hasher.combine(lesson.requiresConfirmationOverride)
        }
        return hasher.finalize()
    }

    /// The sub-areas' default rules (`CDLessonSequenceSettings`) and the
    /// mastery marks on the preceding lessons: the rest of what the engine
    /// reads. Order-independent, since neither comes back in a fixed order.
    static func readinessInputsHash(
        sequenceSettings: [CDLessonSequenceSettings],
        masteryMarks: [String: Set<String>]
    ) -> Int {
        var hasher = Hasher()
        let settings = sequenceSettings.filter { !$0.isDeleted }.map { setting in
            "\(setting.area)|\(setting.sequence)|\(setting.requiresPractice)|\(setting.requiresTeacherConfirmation)"
        }
        hasher.combine(settings.sorted())
        for lessonID in masteryMarks.keys.sorted() {
            hasher.combine(lessonID)
            hasher.combine(masteryMarks[lessonID]?.sorted() ?? [])
        }
        return hasher.finalize()
    }

    /// The mastery marks on each unscheduled plan's preceding lesson: a mark
    /// counts as confirmation (bug hunt 2026-11-03 #5).
    func fetchPrecedingMasteryMarks(
        _ lessonAssignments: [CDLessonAssignment],
        _ lessons: [CDLesson],
        in viewContext: NSManagedObjectContext
    ) -> [String: Set<String>] {
        let unscheduled = lessonAssignments.filter { $0.scheduledFor == nil && !$0.isGiven }
        let lessonIDs = BlockingAlgorithmEngine.precedingLessonIDs(
            for: unscheduled, precedingLessons: BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)
        )
        return PresentationRecordIndex.masteryMarks(lessonIDs: lessonIDs, in: viewContext)
    }

    /// Closed work on the given presentations that gate the backlog (each
    /// unscheduled plan's preceding lesson). The blocking check needs it: a
    /// child who finished her practice has only closed work there, and with
    /// open work alone she read as having none, so "Waiting for work".
    func fetchClosedPrecedingWork(
        _ lessonAssignments: [CDLessonAssignment],
        _ lessons: [CDLesson],
        in viewContext: NSManagedObjectContext
    ) -> [CDWorkModel] {
        let unscheduled = lessonAssignments.filter { $0.scheduledFor == nil && !$0.isGiven }
        let presentationIDs = BlockingAlgorithmEngine.precedingPresentationIDs(
            for: unscheduled, lessons: lessons, allLessonAssignments: lessonAssignments
        )
        guard !presentationIDs.isEmpty else { return [] }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "presentationID IN %@", Array(presentationIDs)),
            NSCompoundPredicate(notPredicateWithSubpredicate: WorkStatus.openPredicate)
        ])
        return viewContext.safeFetch(request)
    }
}
