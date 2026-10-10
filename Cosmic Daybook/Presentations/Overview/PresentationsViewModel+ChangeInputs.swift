// PresentationsViewModel+ChangeInputs.swift
// What `update` reads besides the open work and the assignment table, and the
// hashes it compares to decide whether anything moved.

import CoreData
import Foundation

extension PresentationsViewModel {
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
        _ missWindow: PresentationsMissWindow,
        _ showTestStudents: Bool,
        _ testStudentNamesRaw: String
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(inboxOrderRaw)
        hasher.combine(missWindow)
        hasher.combine(showTestStudents)
        hasher.combine(testStudentNamesRaw)
        return hasher.finalize()
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
