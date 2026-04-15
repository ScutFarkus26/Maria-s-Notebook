import Foundation
import OSLog
import CoreData

/// Service for scheduling and clearing student meetings.
enum MeetingScheduler {
    private static let logger = Logger.students

    /// Schedules a meeting for a student on a given date.
    /// If the student already has a scheduled meeting on a different day, it is replaced.
    /// If the student already has one on the same day, this is a no-op.
    static func scheduleMeeting(studentID: UUID, date: Date, context: NSManagedObjectContext) {
        let normalizedDate = AppCalendar.startOfDay(date)
        let studentIDString = studentID.uuidString

        // Check for existing scheduled meetings for this student
        let existing = fetchAll(studentID: studentIDString, context: context)

        if let first = existing.first {
            if AppCalendar.isSameDay(first.date ?? .distantPast, normalizedDate) {
                return // Already scheduled for this day
            }
            // Update existing to the new date
            first.date = normalizedDate
        } else {
            // Create new
            let meeting = CDScheduledMeeting(context: context)
            meeting.studentIDUUID = studentID
            meeting.date = normalizedDate
        }

        context.safeSave()
    }

    /// Clears all scheduled meetings for a student.
    static func clearMeetings(studentID: UUID, context: NSManagedObjectContext) {
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
    static func clearMeeting(id: UUID, context: NSManagedObjectContext) {
        let targetID = id
        let descriptor: NSFetchRequest<CDScheduledMeeting> = NSFetchRequest(entityName: "ScheduledMeeting")
        descriptor.predicate = NSPredicate(format: "id == %@", targetID as CVarArg)
        if let meeting = context.safeFetch(descriptor).first {
            context.delete(meeting)
            context.safeSave()
        }
    }

    /// Returns the next scheduled meeting date for a student, or nil.
    static func scheduledDate(for studentID: UUID, context: NSManagedObjectContext) -> Date? {
        let studentIDString = studentID.uuidString
        return fetchAll(studentID: studentIDString, context: context).first?.date
    }

    // MARK: - Group Meetings

    /// Schedules a group meeting for multiple students, optionally linked to a work item.
    static func scheduleGroupMeeting(
        participantIDs: [UUID],
        date: Date,
        workID: UUID? = nil,
        context: NSManagedObjectContext
    ) {
        guard !participantIDs.isEmpty else { return }
        let normalizedDate = AppCalendar.startOfDay(date)

        let meeting = CDScheduledMeeting(context: context)
        meeting.isGroupMeeting = true
        meeting.participantStudentIDs = participantIDs.map(\.uuidString)
        meeting.studentID = participantIDs[0].uuidString
        meeting.date = normalizedDate
        meeting.workIDUUID = workID

        context.safeSave()
    }

    /// Returns all scheduled meetings involving a given student
    /// (either as primary student or as a group meeting participant).
    static func scheduledMeetings(involving studentID: UUID, context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        let descriptor = NSFetchRequest<CDScheduledMeeting>(entityName: "ScheduledMeeting")
        descriptor.sortDescriptors = [NSSortDescriptor(keyPath: \CDScheduledMeeting.date, ascending: true)]
        let all = context.safeFetch(descriptor)
        let idString = studentID.uuidString
        return all.filter { $0.allStudentIDs.contains(idString) }
    }

    // MARK: - Private

    private static func fetchAll(studentID: String, context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        let descriptor = NSFetchRequest<CDScheduledMeeting>(entityName: "ScheduledMeeting")
        descriptor.predicate = NSPredicate(format: "studentID == %@", studentID)
        descriptor.sortDescriptors = [NSSortDescriptor(keyPath: \CDScheduledMeeting.date, ascending: true)]
        return context.safeFetch(descriptor)
    }
}
