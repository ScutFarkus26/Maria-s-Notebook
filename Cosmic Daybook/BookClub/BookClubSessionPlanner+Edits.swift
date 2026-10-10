import CoreData
import Foundation

extension BookClubSessionPlanner {

    /// What the session editor's Save writes onto an existing session.
    struct SessionEdits {
        var displayName: String
        var startDate: Date
        var cadenceKind: BookClubCadenceKind
        /// The weekday mask as stored on the session.
        var weekdayMask: Int64
        var cadence: BookClubCadence
        /// Enrolled members, in roster order; leaders rotate through these.
        var roster: [UUID]
        /// Members who left the class: kept on the session, never leaders.
        var departedMembers: [UUID]
        var rotateLeader: Bool
        var notes: String
        /// Every reading, numbered as the session's meetings are.
        var readings: [BookClubReadingItem]
    }

    /// Updates `session` in place. Meetings already held keep their mark, date
    /// and leader; an edited reading label reaches every meeting given that
    /// reading; the meetings not yet held are rebuilt only when the schedule
    /// changed, and only re-led when just the roster or rotation changed.
    /// Doesn't save.
    static func applyEdits(
        _ edits: SessionEdits,
        to session: CDBookClubSession,
        today: Date,
        calendar: Calendar,
        context: NSManagedObjectContext
    ) {
        let startChanged = !calendar.isDate(session.startDate ?? .distantPast, inSameDayAs: edits.startDate)
        let scheduleChanged = startChanged
            || session.cadenceKind != edits.cadenceKind
            || session.meetingWeekdayMask != edits.weekdayMask
        // The rotation the unheld meetings' leaders were picked by, before this
        // edit, so a leader she chose by hand can be told from a rotated one.
        let previousRotation = LeaderRotation(roster: session.studentIDs, rotates: session.rotateLeader)

        session.displayName = edits.displayName
        session.startDate = edits.startDate
        session.cadenceKind = edits.cadenceKind
        session.meetingWeekdayMask = edits.weekdayMask
        session.studentIDs = edits.roster + edits.departedMembers.filter { !edits.roster.contains($0) }
        session.rotateLeader = edits.rotateLeader
        session.notes = edits.notes

        applyLabels(edits.readings, to: session)
        if scheduleChanged {
            let schedule = Schedule(
                readings: edits.readings,
                start: editedScheduleStart(
                    chosen: edits.startDate, startChanged: startChanged,
                    meetings: session.orderedMeetings, today: today, calendar: calendar
                ),
                cadence: edits.cadence,
                roster: edits.roster,
                rotateLeader: edits.rotateLeader
            )
            regenerateUnheldMeetings(of: session, schedule: schedule, calendar: calendar, context: context)
        } else {
            reassignUnheldLeaders(
                of: session,
                from: previousRotation,
                to: LeaderRotation(roster: edits.roster, rotates: edits.rotateLeader)
            )
        }
        session.modifiedAt = Date()
    }

    /// The first day rebuilt meetings may fall on after an edit: the start date
    /// she chose, when she moved it and nothing has been held yet; otherwise the
    /// latest of the start date, today and the day after the last held meeting,
    /// so no new meeting is dated in the past.
    static func editedScheduleStart(
        chosen: Date, startChanged: Bool, meetings: [CDBookClubMeeting], today: Date, calendar: Calendar
    ) -> Date {
        let chosenDay = calendar.startOfDay(for: chosen)
        if startChanged, !meetings.contains(where: \.isCompleted) {
            return chosenDay
        }
        return max(chosenDay, regenerationStart(today: today, meetings: meetings, calendar: calendar))
    }
}
