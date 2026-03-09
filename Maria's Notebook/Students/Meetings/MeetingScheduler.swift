import Foundation
import OSLog
import SwiftData

/// Service for scheduling and clearing student meetings.
enum MeetingScheduler {
    private static let logger = Logger.students

    /// Schedules a meeting for a student on a given date.
    /// If the student already has a scheduled meeting on a different day, it is replaced.
    /// If the student already has one on the same day, this is a no-op.
    static func scheduleMeeting(studentID: UUID, date: Date, context: ModelContext) {
        let normalizedDate = AppCalendar.startOfDay(date)
        let studentIDString = studentID.uuidString

        // Check for existing scheduled meetings for this student
        let existing = fetchAll(studentID: studentIDString, context: context)

        if let first = existing.first {
            if AppCalendar.isSameDay(first.date, normalizedDate) {
                return // Already scheduled for this day
            }
            // Update existing to the new date
            first.date = normalizedDate
        } else {
            // Create new
            let meeting = ScheduledMeeting(studentID: studentID, date: normalizedDate)
            context.insert(meeting)
        }

        context.safeSave()
    }

    /// Clears all scheduled meetings for a student.
    static func clearMeetings(studentID: UUID, context: ModelContext) {
        let studentIDString = studentID.uuidString
        let existing = fetchAll(studentID: studentIDString, context: context)
        for meeting in existing {
            context.delete(meeting)
        }
        if !existing.isEmpty {
            context.safeSave()
        }
    }

    /// Clears a specific scheduled meeting by ID.
    static func clearMeeting(id: UUID, context: ModelContext) {
        let targetID = id
        let descriptor = FetchDescriptor<ScheduledMeeting>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let meeting = context.safeFetch(descriptor).first {
            context.delete(meeting)
            context.safeSave()
        }
    }

    /// Returns the next scheduled meeting date for a student, or nil.
    static func scheduledDate(for studentID: UUID, context: ModelContext) -> Date? {
        let studentIDString = studentID.uuidString
        return fetchAll(studentID: studentIDString, context: context).first?.date
    }

    // MARK: - Private

    private static func fetchAll(studentID: String, context: ModelContext) -> [ScheduledMeeting] {
        let descriptor = FetchDescriptor<ScheduledMeeting>(
            predicate: #Predicate { $0.studentID == studentID },
            sortBy: [SortDescriptor(\ScheduledMeeting.date)]
        )
        return context.safeFetch(descriptor)
    }
}
