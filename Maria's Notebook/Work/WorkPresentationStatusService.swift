import Foundation
import OSLog
import SwiftData
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
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return "Scheduled for \(formatter.string(from: date))"
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
    /// - Parameters:
    ///   - work: The work item to check
    ///   - modelContext: SwiftData model context
    /// - Returns: The presentation status
    static func findNextPresentationStatus(for work: WorkModel, modelContext: ModelContext) -> PresentationStatus {
        // Validate that we have valid IDs
        guard UUID(uuidString: work.lessonID) != nil,
              UUID(uuidString: work.studentID) != nil else {
            return .notFound
        }
        
        // First, check for scheduled presentations (LessonAssignment with state = scheduled)
        let lessonIDString = work.lessonID
        let scheduledDescriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate<LessonAssignment> { assignment in
                assignment.lessonID == lessonIDString &&
                assignment.stateRaw == "scheduled"
            },
            sortBy: [SortDescriptor(\.scheduledFor, order: .forward)]
        )
        
        do {
            let scheduledAssignments = try modelContext.fetch(scheduledDescriptor)
            // Filter to only unpresented assignments with this student
            let relevantScheduled = scheduledAssignments.filter { assignment in
                assignment.presentedAt == nil &&
                assignment.studentIDs.contains(work.studentID)
            }
            
            if let nextScheduled = relevantScheduled.first,
               let scheduledDate = nextScheduled.scheduledFor {
                return .scheduled(date: scheduledDate)
            }
        } catch {
            logger.warning("Failed to fetch scheduled LessonAssignment: \(error)")
        }

        // Next, check for draft presentations (LessonAssignment with state = draft, not scheduled)
        let draftDescriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate<LessonAssignment> { assignment in
                assignment.lessonID == lessonIDString &&
                assignment.stateRaw == "draft"
            }
        )
        
        do {
            let draftAssignments = try modelContext.fetch(draftDescriptor)
            // Filter to only unpresented, unscheduled assignments with this student
            let relevantDrafts = draftAssignments.filter { assignment in
                assignment.scheduledFor == nil &&
                assignment.presentedAt == nil &&
                assignment.studentIDs.contains(work.studentID)
            }
            
            if let inboxAssignment = relevantDrafts.first {
                let otherStudents = inboxAssignment.studentIDs.filter { $0 != work.studentID }
                
                if otherStudents.isEmpty {
                    return .inInbox(students: [work.studentID])
                } else {
                    return .inInbox(students: inboxAssignment.studentIDs)
                }
            }
        } catch {
            logger.warning("Failed to fetch draft LessonAssignment: \(error)")
        }

        return .notFound
    }
}

extension WorkPresentationStatusService.PresentationStatus {
    var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }
}
