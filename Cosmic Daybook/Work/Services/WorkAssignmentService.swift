//
//  WorkAssignmentService.swift
//  Cosmic Daybook
//
//  Giving work to one child or several: the one way (domain logic review
//  2026-11-20, A3 and R22). Quick New Work and Claude's `assign_work` both
//  come through here, so they make the same rows:
//
//  - one row per child (`WorkRepository.createWork`), every copy carrying the
//    same `assignmentID`, none of them a shared row;
//  - the first check-in through `WorkCheckInService.addCheckIn`, so a weekend
//    or a day off lands on the next school day (Quick New Work used to make
//    it on the day picked, closed or not);
//  - each copy naming the others, written once (`link`).
//
//  Nothing saves here; the caller owns the save.
//

import CoreData
import Foundation

struct WorkAssignmentService {
    let context: NSManagedObjectContext

    /// What to give, and to whom.
    struct Request {
        var lessonID: UUID
        var studentIDs: [UUID]
        /// Nil leaves the title empty, as New Work does for an untitled piece.
        var title: String?
        /// Nil takes `createWork`'s default: Practice once she has been given
        /// the lesson, Follow-Up otherwise.
        var kind: WorkKind?
        /// The due date the guide set, if any. Never the check day.
        var dueDate: Date?
        var sampleWorkID: UUID?
        /// How a group's check-ins run; only kept when there is a group.
        var checkInStyle: CheckInStyle?
        var checkIn: CheckIn?
    }

    /// The first check-in: the day asked for, and what it is for.
    struct CheckIn {
        var day: Date
        var purpose: String
    }

    /// What `create` made.
    struct Assigned {
        /// One row per child, in the order asked.
        let works: [CDWorkModel]
        /// The day the check-ins are on, when one was asked for.
        let checkInDay: Date?
        /// The day asked for, when it wasn't a school day and the check-ins
        /// moved forward to `checkInDay`.
        let checkInAskedFor: Date?
    }

    /// Makes every child's row. Throws when a child has left the class
    /// (`WorkRepository.AssignmentError`); rows already made stay in the
    /// context for the caller to take back.
    func create(_ request: Request) throws -> Assigned {
        let repository = WorkRepository(context: context)
        let isGroup = request.studentIDs.count > 1
        let assignmentID = isGroup ? UUID().uuidString : nil
        var works: [CDWorkModel] = []
        var checkInDay: Date?
        var askedFor: Date?

        for studentID in request.studentIDs {
            let work = try repository.createWork(
                studentID: studentID,
                lessonID: request.lessonID,
                title: request.title,
                kind: request.kind,
                scheduledDate: request.dueDate,
                sampleWorkID: request.sampleWorkID,
                assignmentID: assignmentID,
                saveImmediately: false
            )
            if isGroup, let style = request.checkInStyle {
                work.checkInStyle = style
            }
            if let checkIn = request.checkIn,
               case let .added(made, moved) = WorkCheckInService(context: context).addCheckIn(
                   to: work, on: checkIn.day, purpose: checkIn.purpose, note: nil
               ) {
                checkInDay = made.date
                askedFor = moved
            }
            works.append(work)
        }
        Self.link(works, in: context)
        return Assigned(works: works, checkInDay: checkInDay, checkInAskedFor: askedFor)
    }

    /// Makes `copies` one assignment given to a group: each names the others
    /// (so "with Leshem" reads on every copy), they share one `assignmentID`,
    /// and none is a shared row. A report started for several children is
    /// linked here too. One copy alone is left as it is.
    static func link(_ copies: [CDWorkModel], in context: NSManagedObjectContext) {
        guard copies.count > 1 else { return }
        let assignmentID = copies.compactMap(\.assignmentID).first { !$0.isEmpty } ?? UUID().uuidString
        for work in copies {
            work.assignmentID = assignmentID
            work.isSharedRow = false
            let named = Set(WorkLogService.participants(of: work).map(\.studentID))
            for other in copies where other !== work && !named.contains(other.studentID) {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = other.studentID
                participant.work = work
            }
        }
    }
}
