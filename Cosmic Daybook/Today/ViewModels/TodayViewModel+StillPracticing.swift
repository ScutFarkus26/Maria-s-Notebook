// TodayViewModel+StillPracticing.swift
// "Still practicing: Ora L (The Distributive Law)" on Today's lesson rows and
// Next card (plan "Cut unused features and close the lesson loop", Phase 4):
// the children on a lesson not yet given who still have practice open on an
// earlier lesson in its sequence (`WorkToShowFirst`), so the guide sees it
// before she gives the next one. One read for the whole day's lessons.

import CoreData
import Foundation

extension TodayViewModel {

    /// The line for `assignment`, when one of its children is still practicing.
    func stillPracticingLine(for assignment: CDLessonAssignment) -> String? {
        assignment.id.flatMap { stillPracticingLines[$0] }
    }

    /// Each pending lesson's line, keyed by presentation id; a lesson with
    /// nobody still practicing is absent. Nothing is read without the library
    /// (the view hands it in on appear).
    static func stillPracticingLines(
        for assignments: [CDLessonAssignment],
        lessons: [CDLesson]?,
        names: (UUID) -> String?,
        in context: NSManagedObjectContext
    ) -> [UUID: String] {
        guard let lessons, !lessons.isEmpty else { return [:] }
        var requests: [UUID: WorkToShowFirst.Request] = [:]
        for assignment in assignments where !assignment.isPresented {
            guard let id = assignment.id else { continue }
            let children = Set(assignment.resolvedStudentIDs)
            guard !children.isEmpty else { continue }
            requests[id] = WorkToShowFirst.Request(
                lessonID: assignment.resolvedLessonID.uuidString, studentIDs: children
            )
        }
        guard !requests.isEmpty else { return [:] }
        let found = WorkToShowFirst.find(requests, sequences: WorkToShowFirst.Sequences(lessons: lessons), in: context)
        return found.compactMapValues { byChild in
            WorkToShowFirst.stillPracticingLine(byChild, name: { names($0) ?? "A child" })
        }
    }
}
