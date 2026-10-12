import Foundation
import OSLog
import CoreData

/// Service for scheduling and clearing student meetings.
enum MeetingScheduler {
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
    /// held, and takes her off a group booking she was part of, without
    /// saving. A booking on `date` or before it is the one just completed; a
    /// later one is the next meeting and stays. A group booking stays for the
    /// children not yet met and goes once nobody is left in it (bug hunt
    /// 2026-10-11, #27). Returns the day the completed booking was for, or
    /// nil when there was none.
    static func completeBooking(
        studentID: UUID, heldOn date: Date, context: NSManagedObjectContext
    ) -> Date? {
        let held = AppCalendar.startOfDay(date)
        let isDue: (CDScheduledMeeting) -> Bool = {
            AppCalendar.startOfDay($0.date ?? .distantFuture) <= held
        }
        let individual = fetchAll(studentID: studentID.uuidString, context: context).filter {
            !$0.isGroupMeeting && isDue($0)
        }
        let groups = groupBookings(including: studentID, context: context).filter(isDue)
        for booking in individual {
            context.delete(booking)
        }
        for booking in groups {
            remove(studentID, from: booking, context: context)
        }
        return (individual + groups).compactMap(\.date).max()
    }

    /// Clears the student's own bookings. Group sittings she is part of stay:
    /// they are the group's booking, not hers, and a group stores its first
    /// participant in `studentID`, so matching on that alone deleted the
    /// group's meeting (bug hunt 2026-10-10, Part 2 #69).
    static func clearMeetings(studentID: UUID, context: NSManagedObjectContext) {
        let existing = fetchAll(studentID: studentID.uuidString, context: context).filter { !$0.isGroupMeeting }
        for meeting in existing {
            context.delete(meeting)
        }
        if !existing.isEmpty {
            context.safeSave()
        }
    }

    /// Clears a scheduled meeting by ID, whoever is in it: Today's Remove.
    static func clearMeeting(id: UUID, context: NSManagedObjectContext) {
        if let meeting = context.object(CDScheduledMeeting.self, id: id) {
            context.delete(meeting)
            context.safeSave()
        }
    }

    /// Clears the booking `studentID`'s meeting was opened from, once it has
    /// been held. Her own booking is deleted; a group booking loses only her
    /// and is deleted once nobody is left, so the other children's meeting
    /// stays on Today (bug hunt 2026-10-11, #27). Saves when anything changed.
    static func clearMeeting(id: UUID, completedFor studentID: UUID, context: NSManagedObjectContext) {
        guard let meeting = context.object(CDScheduledMeeting.self, id: id) else { return }
        if meeting.isGroupMeeting {
            // Filing the meeting (completeBooking) usually took her off already.
            guard includes(studentID, meeting) else { return }
            remove(studentID, from: meeting, context: context)
        } else {
            context.delete(meeting)
        }
        context.safeSave()
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

    // MARK: - Private

    /// The student's own booking, if any. A group sitting stores its first
    /// participant in `studentID`, so matching on that alone would move the
    /// group's meeting when the guide books a child's individual one. A group
    /// booking the others have all left (completed, #27) is hers alone, so it
    /// counts when she has no individual one, rather than gaining a twin.
    private static func individualBooking(
        studentID: UUID, context: NSManagedObjectContext
    ) -> CDScheduledMeeting? {
        let booked = fetchAll(studentID: studentID.uuidString, context: context)
        return booked.first { !$0.isGroupMeeting }
            ?? booked.first { $0.allStudentIDs == [studentID.uuidString] }
    }

    /// The group bookings `studentID` is in. A group's participants are
    /// stored as encoded data, so they are matched in memory; there are few.
    private static func groupBookings(
        including studentID: UUID, context: NSManagedObjectContext
    ) -> [CDScheduledMeeting] {
        let request = CDFetchRequest(CDScheduledMeeting.self)
        request.predicate = NSPredicate(format: "isGroupMeeting == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDScheduledMeeting.date, ascending: true)]
        return context.safeFetch(request).filter { includes(studentID, $0) }
    }

    private static func includes(_ studentID: UUID, _ meeting: CDScheduledMeeting) -> Bool {
        meeting.allStudentIDs.contains { UUID(uuidString: $0) == studentID }
    }

    /// Takes `studentID` off a group booking, deleting it when she was the
    /// last, or when everyone left in it has left the class (review
    /// 2026-10-11). A child not on this device yet counts as still here.
    /// `studentID` keeps holding the first participant left.
    private static func remove(
        _ studentID: UUID, from meeting: CDScheduledMeeting, context: NSManagedObjectContext
    ) {
        let rest = meeting.allStudentIDs.filter { UUID(uuidString: $0) != studentID }
        let anyoneStillHere = rest.contains { id in
            guard let uuid = UUID(uuidString: id),
                  let student = context.object(CDStudent.self, id: uuid) else { return true }
            return student.isEnrolled
        }
        guard let first = rest.first, anyoneStillHere else {
            context.delete(meeting)
            return
        }
        meeting.participantStudentIDs = rest
        meeting.studentID = first
    }

    private static func fetchAll(studentID: String, context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        let descriptor = CDFetchRequest(CDScheduledMeeting.self)
        descriptor.predicate = NSPredicate(format: "studentID == %@", studentID)
        descriptor.sortDescriptors = [NSSortDescriptor(keyPath: \CDScheduledMeeting.date, ascending: true)]
        return context.safeFetch(descriptor)
    }
}
