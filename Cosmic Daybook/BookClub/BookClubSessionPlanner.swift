import CoreData
import Foundation

/// Changes to a book club session's meetings that keep what already happened.
///
/// A meeting's `ordinal` is the position of the reading it was given (1 = the
/// first reading): `BookClubScheduleGenerator` numbers meetings by reading, and
/// everything here keeps that so. So the readings a session has met are the
/// ordinals of its held meetings, whatever their labels say and however many
/// meetings there are.
///
/// Editing a session and Regenerate both used to delete meetings and make new
/// ones from a count: a held meeting lost its mark and its leader, and the
/// readings after it could be dated in the past, repeated, or skipped. Now a
/// held meeting is never touched, and only the readings no held meeting covered
/// get new meetings, from a start day that is never before today or before the
/// last held meeting.
enum BookClubSessionPlanner {

    // MARK: - Readings

    /// The readings the session works through, in order: the packet's, with the
    /// label the session's meetings carry where one has a meeting (a label edited
    /// for this session wins), plus any meeting's reading past the packet's end.
    static func readings(
        packetItems: [BookClubReadingItem], meetings: [CDBookClubMeeting]
    ) -> [BookClubReadingItem] {
        var labelsByOrdinal: [Int: String] = [:]
        // Held meetings first, so their label wins over a stray duplicate's.
        for meeting in meetings.sorted(by: { $0.isCompleted && !$1.isCompleted }) {
            let ordinal = Int(meeting.ordinal)
            guard ordinal > 0, labelsByOrdinal[ordinal] == nil else { continue }
            labelsByOrdinal[ordinal] = meeting.readingLabel
        }
        var byOrdinal: [Int: BookClubReadingItem] = [:]
        for item in packetItems where item.ordinal > 0 && byOrdinal[item.ordinal] == nil {
            var reading = item
            if let label = labelsByOrdinal[item.ordinal] { reading.label = label }
            byOrdinal[item.ordinal] = reading
        }
        for (ordinal, label) in labelsByOrdinal where byOrdinal[ordinal] == nil {
            byOrdinal[ordinal] = BookClubReadingItem(ordinal: ordinal, label: label)
        }
        return byOrdinal.values.sorted { $0.ordinal < $1.ordinal }
    }

    /// The readings no held meeting covered.
    static func unmetReadings(
        _ readings: [BookClubReadingItem], meetings: [CDBookClubMeeting]
    ) -> [BookClubReadingItem] {
        let met = Set(meetings.filter(\.isCompleted).map { Int($0.ordinal) })
        return readings.filter { !met.contains($0.ordinal) }
    }

    // MARK: - Dates

    /// The day after the last held meeting, or nil when none is held.
    static func dayAfterLastHeldMeeting(_ meetings: [CDBookClubMeeting], calendar: Calendar) -> Date? {
        guard let last = meetings.filter(\.isCompleted).compactMap(\.date).max() else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))
    }

    /// Where Regenerate starts the remaining meetings: the later of today and the
    /// day after the last held meeting.
    static func regenerationStart(today: Date, meetings: [CDBookClubMeeting], calendar: Calendar) -> Date {
        let todayStart = calendar.startOfDay(for: today)
        guard let afterHeld = dayAfterLastHeldMeeting(meetings, calendar: calendar) else { return todayStart }
        return max(todayStart, afterHeld)
    }

    /// The cadence a stored session meets on.
    static func cadence(for session: CDBookClubSession, calendar: Calendar) -> BookClubCadence {
        let weekday = session.startDate.map { calendar.component(.weekday, from: $0) } ?? 2
        switch session.cadenceKind {
        case .weekly: return .weekly(weekday: weekday)
        case .biweekly: return .biweekly(weekday: weekday)
        case .custom:
            let mask = session.meetingWeekdayMask == 0 ? (Int64(1) << weekday) : session.meetingWeekdayMask
            return .custom(weekdayMask: mask)
        }
    }

    // MARK: - Meetings

    /// What the meetings not yet held are rebuilt from.
    struct Schedule {
        /// Every reading of the session, by `readings(packetItems:meetings:)`.
        var readings: [BookClubReadingItem]
        /// The first day a new meeting may fall on.
        var start: Date
        var cadence: BookClubCadence
        /// The members leaders rotate through, in roster order.
        var roster: [UUID]
        var rotateLeader: Bool
        /// The rotation the unheld meetings' leaders were picked by, when
        /// leaders she picked by hand should outlast the rebuild (an edit to
        /// the session's day or start); nil re-leads every rebuilt meeting.
        var keepingLeadersPickedAgainst: LeaderRotation?
    }

    /// Replaces the session's unheld meetings with new ones for the readings no
    /// held meeting covered, dated by the schedule's cadence from its start. Held
    /// meetings are left exactly as they are. Leaders rotate through the roster by
    /// reading, as a freshly generated schedule's do, except that a reading
    /// whose unheld meeting had a leader picked by hand keeps her, while she is
    /// still on the roster (`Schedule.keepingLeadersPickedAgainst`; bug hunt
    /// 2026-10-29, #22: a new day or start date used to wipe them). Updates
    /// `endDate`. Doesn't save.
    @discardableResult
    static func regenerateUnheldMeetings(
        of session: CDBookClubSession,
        schedule: Schedule,
        calendar: Calendar,
        context: NSManagedObjectContext
    ) -> [CDBookClubMeeting] {
        let meetings = session.orderedMeetings
        let unmet = unmetReadings(schedule.readings, meetings: meetings)
        let handPicked = schedule.keepingLeadersPickedAgainst.map {
            handPickedLeaders(of: meetings, against: $0, roster: schedule.roster)
        } ?? [:]
        for meeting in meetings where !meeting.isCompleted {
            context.delete(meeting)
        }

        let dated = BookClubScheduleGenerator.generate(
            startDate: schedule.start,
            cadence: schedule.cadence,
            readingItems: unmet,
            roster: [],
            rotateLeader: false,
            calendar: calendar
        )
        var created: [CDBookClubMeeting] = []
        for (reading, generated) in zip(unmet, dated) {
            let meeting = CDBookClubMeeting(context: context)
            meeting.sessionID = session.id?.uuidString ?? ""
            meeting.session = session
            meeting.ordinal = Int32(reading.ordinal)
            meeting.date = generated.date
            meeting.readingLabel = reading.label
            meeting.leaderStudentID = (handPicked[reading.ordinal] ?? leader(
                forReading: reading.ordinal, roster: schedule.roster, rotate: schedule.rotateLeader
            ))?.uuidString ?? ""
            created.append(meeting)
        }
        updateEndDate(of: session)
        return created
    }

    /// The leaders she picked by hand for unheld meetings, by reading: any
    /// leader when `rotation` didn't rotate, otherwise one other than the
    /// rotation gave that reading. Only those still on `roster` count.
    private static func handPickedLeaders(
        of meetings: [CDBookClubMeeting], against rotation: LeaderRotation, roster: [UUID]
    ) -> [Int: UUID] {
        var picked: [Int: UUID] = [:]
        for meeting in meetings where !meeting.isCompleted {
            let ordinal = Int(meeting.ordinal)
            guard let current = meeting.leaderStudentUUID, roster.contains(current),
                  current != rotation.leader(forReading: ordinal), picked[ordinal] == nil else { continue }
            picked[ordinal] = current
        }
        return picked
    }

    /// Writes edited reading labels onto every meeting given that reading, held
    /// or not.
    static func applyLabels(_ readings: [BookClubReadingItem], to session: CDBookClubSession) {
        let labels = Dictionary(readings.map { ($0.ordinal, $0.label) }, uniquingKeysWith: { first, _ in first })
        for meeting in session.orderedMeetings {
            guard let label = labels[Int(meeting.ordinal)], label != meeting.readingLabel else { continue }
            meeting.readingLabel = label
            meeting.modifiedAt = Date()
        }
    }

    /// How a session picks its leaders: by rotating through a roster, or not.
    struct LeaderRotation {
        var roster: [UUID]
        var rotates: Bool

        /// The leader this rotation gives a reading, if it rotates.
        func leader(forReading ordinal: Int) -> UUID? {
            BookClubSessionPlanner.leader(forReading: ordinal, roster: roster, rotate: rotates)
        }
    }

    /// Brings the leaders of the meetings not yet held in line with a changed
    /// roster or rotation, keeping the ones she picked by hand. With rotation
    /// off, only a leader no longer on the roster is cleared. With rotation on,
    /// a meeting is re-rotated only when its leader is still the one the old
    /// rotation gave it, it has none, or its leader left the roster. Held
    /// meetings keep the leader they had.
    static func reassignUnheldLeaders(
        of session: CDBookClubSession, from old: LeaderRotation, to new: LeaderRotation
    ) {
        for meeting in session.orderedMeetings where !meeting.isCompleted {
            let ordinal = Int(meeting.ordinal)
            let current = meeting.leaderStudentUUID
            let offRoster = current.map { !new.roster.contains($0) } ?? false
            let target: UUID?
            if !new.rotates {
                guard offRoster else { continue }
                target = nil
            } else {
                let pickedByRotation = current == old.leader(forReading: ordinal)
                guard pickedByRotation || current == nil || offRoster else { continue }
                target = new.leader(forReading: ordinal)
            }
            let leader = target?.uuidString ?? ""
            guard leader != meeting.leaderStudentID else { continue }
            meeting.leaderStudentID = leader
            meeting.modifiedAt = Date()
        }
    }

    /// The session ends on its last meeting.
    static func updateEndDate(of session: CDBookClubSession) {
        let dates = session.meetingsSet.filter { !$0.isDeleted }.compactMap(\.date)
        if let last = dates.max() {
            session.endDate = last
        }
    }

    private static func leader(forReading ordinal: Int, roster: [UUID], rotate: Bool) -> UUID? {
        guard rotate, !roster.isEmpty, ordinal > 0 else { return nil }
        return roster[(ordinal - 1) % roster.count]
    }
}
