import Foundation
import OSLog
import CoreData

/// Service for scheduling and clearing student meetings.
enum MeetingScheduler {
    private static let logger = Logger.students

    /// What ``bookMeeting(studentID:date:purpose:workID:context:)`` did with
    /// the booking it hands back.
    enum BookingOutcome: Equatable {
        case created
        case unchanged
        case moved(from: Date)
    }

    /// Schedules a meeting for a student on a given date and saves.
    /// If the student already has a scheduled meeting on a different day, it is replaced.
    /// If the student already has one on the same day, this is a no-op.
    static func scheduleMeeting(studentID: UUID, date: Date, context: NSManagedObjectContext) {
        bookMeeting(studentID: studentID, date: date, context: context)
        context.safeSave()
    }

    /// Books a student's individual meeting on a day without saving, so a
    /// caller can fold it into its own save and report a failure.
    ///
    /// A student holds one individual booking: an existing one on another day
    /// is moved rather than joined by a second, and one on the same day is
    /// kept. Group sittings the student is part of are not touched — they are
    /// the group's booking, not the student's. `purpose` and `workID` are
    /// written when given and left as they were when nil.
    @discardableResult
    static func bookMeeting(
        studentID: UUID,
        date: Date,
        purpose: String? = nil,
        workID: UUID? = nil,
        context: NSManagedObjectContext
    ) -> (meeting: CDScheduledMeeting, outcome: BookingOutcome) {
        let normalizedDate = AppCalendar.startOfDay(date)
        let meeting: CDScheduledMeeting
        let outcome: BookingOutcome

        if let existing = individualBooking(studentID: studentID, context: context) {
            meeting = existing
            if let booked = existing.date, AppCalendar.isSameDay(booked, normalizedDate) {
                outcome = .unchanged
            } else {
                outcome = .moved(from: existing.date ?? normalizedDate)
                existing.date = normalizedDate
            }
        } else {
            meeting = CDScheduledMeeting(context: context)
            meeting.studentIDUUID = studentID
            meeting.date = normalizedDate
            outcome = .created
        }
        if let purpose {
            meeting.purpose = purpose
        }
        if let workID {
            meeting.workIDUUID = workID
        }
        return (meeting, outcome)
    }

    /// Deletes the student's individual booking once the meeting has been
    /// held, without saving. A booking on `date` or before it is the one just
    /// completed; a later one is the next meeting and stays. Returns the day
    /// the completed booking was for, or nil when there was none.
    static func completeBooking(
        studentID: UUID, heldOn date: Date, context: NSManagedObjectContext
    ) -> Date? {
        let held = AppCalendar.startOfDay(date)
        let completed = fetchAll(studentID: studentID.uuidString, context: context).filter {
            !$0.isGroupMeeting && AppCalendar.startOfDay($0.date ?? .distantFuture) <= held
        }
        guard !completed.isEmpty else { return nil }
        for booking in completed {
            context.delete(booking)
        }
        // fetchAll sorts ascending, so the last is the most recent one completed.
        return completed.last?.date
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
        if let meeting = context.object(CDScheduledMeeting.self, id: id) {
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

    /// Schedules a sequence meeting for multiple students, optionally linked to a work item.
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
    /// (either as primary student or as a sequence meeting participant).
    static func scheduledMeetings(involving studentID: UUID, context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        let descriptor = NSFetchRequest<CDScheduledMeeting>(entityName: "ScheduledMeeting")
        descriptor.sortDescriptors = [NSSortDescriptor(keyPath: \CDScheduledMeeting.date, ascending: true)]
        let all = context.safeFetch(descriptor)
        let idString = studentID.uuidString
        return all.filter { $0.allStudentIDs.contains(idString) }
    }

    // MARK: - Private

    /// The student's own booking, if any. A group sitting stores its first
    /// participant in `studentID`, so matching on that alone would move the
    /// group's meeting when the guide books a child's individual one.
    private static func individualBooking(
        studentID: UUID, context: NSManagedObjectContext
    ) -> CDScheduledMeeting? {
        fetchAll(studentID: studentID.uuidString, context: context).first { !$0.isGroupMeeting }
    }

    private static func fetchAll(studentID: String, context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        let descriptor = NSFetchRequest<CDScheduledMeeting>(entityName: "ScheduledMeeting")
        descriptor.predicate = NSPredicate(format: "studentID == %@", studentID)
        descriptor.sortDescriptors = [NSSortDescriptor(keyPath: \CDScheduledMeeting.date, ascending: true)]
        return context.safeFetch(descriptor)
    }
}
