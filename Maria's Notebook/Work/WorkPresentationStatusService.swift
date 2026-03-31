import Foundation
import OSLog
import CoreData
import SwiftUI

/// Service to determine the presentation status of the next presentation for a work item
struct WorkPresentationStatusService {
    private static let logger = Logger.work

    /// Status of the next presentation for a work item
    enum PresentationStatus {
        case scheduled(date: Date)
        case inInbox(students: [String])
        case withOtherStudents(students: [String])
        case notFound

        var displayText: String {
            switch self {
            case .scheduled(let date):
                return "Scheduled for \(DateFormatters.mediumDate.string(from: date))"
            case .inInbox(let students):
                if students.count == 1 {
                    return "In inbox (ready to present)"
                } else {
                    return "In inbox with \(students.count) students"
                }
            case .withOtherStudents(let students):
                if students.count == 1 {
                    return "Waiting with 1 other student"
                } else {
                    return "Waiting with \(students.count) other students"
                }
            case .notFound:
                return "No upcoming presentation"
            }
        }

        var iconName: String {
            switch self {
            case .scheduled:
                return "calendar.badge.clock"
            case .inInbox:
                return "tray.fill"
            case .withOtherStudents:
                return "person.2.fill"
            case .notFound:
                return "questionmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .scheduled:
                return .blue
            case .inInbox:
                return .green
            case .withOtherStudents:
                return .orange
            case .notFound:
                return .gray
            }
        }
    }

    /// Finds the next presentation status for a work item
    static func findNextPresentationStatus(for work: CDWorkModel, context: NSManagedObjectContext) -> PresentationStatus {
        guard UUID(uuidString: work.lessonID) != nil,
              UUID(uuidString: work.studentID) != nil else {
            return .notFound
        }

        // First, check for scheduled presentations (CDLessonAssignment with state = scheduled)
        let lessonIDString = work.lessonID
        let scheduledRequest = CDFetchRequest(CDLessonAssignment.self)
        scheduledRequest.predicate = NSPredicate(
            format: "lessonID == %@ AND stateRaw == %@",
            lessonIDString, "scheduled"
        )
        scheduledRequest.sortDescriptors = [NSSortDescriptor(key: "scheduledFor", ascending: true)]

        do {
            let scheduledAssignments = try context.fetch(scheduledRequest)
            let relevantScheduled = scheduledAssignments.filter { assignment in
                assignment.presentedAt == nil &&
                (assignment.studentIDs as? [String] ?? []).contains(work.studentID)
            }

            if let nextScheduled = relevantScheduled.first,
               let scheduledDate = nextScheduled.scheduledFor {
                return .scheduled(date: scheduledDate)
            }
        } catch {
            logger.warning("Failed to fetch scheduled CDLessonAssignment: \(error)")
        }

        // Next, check for draft presentations
        let draftRequest = CDFetchRequest(CDLessonAssignment.self)
        draftRequest.predicate = NSPredicate(
            format: "lessonID == %@ AND stateRaw == %@",
            lessonIDString, "draft"
        )

        do {
            let draftAssignments = try context.fetch(draftRequest)
            let relevantDrafts = draftAssignments.filter { assignment in
                assignment.scheduledFor == nil &&
                assignment.presentedAt == nil &&
                (assignment.studentIDs as? [String] ?? []).contains(work.studentID)
            }

            if let inboxAssignment = relevantDrafts.first {
                let studentIDsArray = (inboxAssignment.studentIDs as? [String]) ?? []
                let otherStudents = studentIDsArray.filter { $0 != work.studentID }

                if otherStudents.isEmpty {
                    return .inInbox(students: [work.studentID])
                } else {
                    return .inInbox(students: studentIDsArray)
                }
            }
        } catch {
            logger.warning("Failed to fetch draft CDLessonAssignment: \(error)")
        }

        return .notFound
    }
}

// Deprecated ModelContext overloads removed - no longer needed with Core Data.

extension WorkPresentationStatusService.PresentationStatus {
    var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }
}
