// PresentationSession+Records.swift
// What a presentation already has on record, read when How It Went opens,
// and each child's timed check-in day for a sheet that starts from nothing.

import CoreData
import Foundation

extension PresentationSession {

    /// Each child's check-in day from `PracticeCheckInTiming`, as chat files
    /// practice: the school day before her next lesson in the sequence, or
    /// three school days after this one.
    static func timedCheckInDays(
        lesson: CDLesson, givenOn: Date?, studentIDs: [UUID], lessons: [CDLesson], context: NSManagedObjectContext
    ) -> [UUID: Date] {
        guard let lessonID = lesson.id, !studentIDs.isEmpty else { return [:] }
        return PracticeCheckInTiming.checkInDays(
            lessonID: lessonID.uuidString, givenOn: givenOn ?? Date(), studentIDs: Set(studentIDs),
            sequences: WorkToShowFirst.Sequences(lessons: lessons), in: context
        )
    }

    // MARK: - Reading the records

    struct AppliedState: Equatable {
        var decisions: [UUID: CaptureFollowUp]
        /// Children with open work who are also confirmed ready for the next lesson.
        var alsoReady: Set<UUID> = []
        var checkIn: PresentationCheckIn

        var choices: [UUID: PresentationChoice] {
            decisions.reduce(into: [:]) { choices, entry in
                choices[entry.key] = PresentationChoice(entry.value, alsoReady: alsoReady.contains(entry.key))
            }
        }
    }

    /// Each child's standing decision, read from her follow-up row and the work
    /// this presentation gave her: a resolved re-present or next-lesson row,
    /// open practice or follow-up work (ready as well when the presentation
    /// confirms her), and otherwise keep watching.
    static func appliedState(presentationID: UUID, in context: NSManagedObjectContext) -> AppliedState {
        let rows = PresentationFollowUpService.rows(for: presentationID, in: context)
        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = NSPredicate(format: "presentationID == %@", presentationID.uuidString)
        let openWork = context.safeFetch(workRequest).filter { $0.status.isOpen }
        let workByStudent = Dictionary(grouping: openWork, by: \.studentID)

        var decisions: [UUID: CaptureFollowUp] = [:]
        var checkInDay: Date?
        for row in rows {
            guard let studentID = UUID(uuidString: row.studentID) else { continue }
            if row.followUpResolvedAt != nil, let resolution = row.followUpResolution {
                switch resolution {
                case .supportOrRepresent: decisions[studentID] = .represent
                case .readyForNextPresentation: decisions[studentID] = .readyForNextLesson
                case .continueIndependentWork, .noFurtherFollowUp: decisions[studentID] = .continueObserving
                }
                continue
            }
            let kinds = Set((workByStudent[row.studentID] ?? []).compactMap(\.kind))
            if kinds.contains(.practiceLesson) {
                decisions[studentID] = .practice
            } else if kinds.contains(.followUpAssignment) {
                decisions[studentID] = .followUpWork
            } else {
                decisions[studentID] = .continueObserving
            }
            if checkInDay == nil, row.hasOpenFollowUp, row.followUpAction == .checkWork {
                checkInDay = row.followUpReviewAt
            }
        }
        let assignmentRequest = CDFetchRequest(CDLessonAssignment.self)
        assignmentRequest.predicate = NSPredicate(format: "id == %@", presentationID as CVarArg)
        assignmentRequest.fetchLimit = 1
        let assignment = context.safeFetch(assignmentRequest).first
        let alsoReady = Set(decisions.keys.filter { id in
            decisions[id]?.createsWork == true && assignment?.isStudentConfirmed(id) == true
        })
        return AppliedState(decisions: decisions, alsoReady: alsoReady, checkIn: PresentationCheckIn(day: checkInDay))
    }
}
