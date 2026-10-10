import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, Part 2 #73 and #74: editing a Book Club session deleted
/// and remade every meeting (losing every "held" mark and reassigned leader),
/// and Regenerate dated the remaining meetings from the session's first day
/// (in the past) and picked readings by a count of held meetings.
@Suite("Book Club session edit and Regenerate (fix 10-10 J1)")
@MainActor
struct BookClubSessionFix1010J1Tests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private let readings: [BookClubReadingItem] = (1...4).map {
        BookClubReadingItem(ordinal: $0, label: "Chapters \($0 * 2 - 1)–\($0 * 2)")
    }

    /// A weekly session on Mondays from Sept 7, 2026, one meeting per reading,
    /// leaders rotating through `roster`.
    private func seedSession(
        roster: [UUID], in context: NSManagedObjectContext
    ) throws -> CDBookClubSession {
        let session = CDBookClubSession(context: context)
        let start = try day(2026, 9, 7)
        session.startDate = start
        session.cadenceKind = .weekly
        session.meetingWeekdayMask = Int64(1) << 2
        session.studentIDs = roster
        session.rotateLeader = true
        let generated = BookClubScheduleGenerator.generate(
            startDate: start, cadence: .weekly(weekday: 2), readingItems: readings,
            roster: roster, rotateLeader: true, calendar: calendar
        )
        for gen in generated {
            let meeting = CDBookClubMeeting(context: context)
            meeting.session = session
            meeting.sessionID = session.id?.uuidString ?? ""
            meeting.ordinal = Int32(gen.ordinal)
            meeting.date = gen.date
            meeting.readingLabel = gen.readingLabel
            meeting.leaderStudentID = gen.leaderStudentID?.uuidString ?? ""
        }
        #expect(CoreDataTestHelpers.save(context))
        return session
    }

    private func edits(
        for session: CDBookClubSession, roster: [UUID], departed: [UUID] = []
    ) -> BookClubSessionPlanner.SessionEdits {
        BookClubSessionPlanner.SessionEdits(
            displayName: session.displayName,
            startDate: session.startDate ?? Date(),
            cadenceKind: session.cadenceKind,
            weekdayMask: session.meetingWeekdayMask,
            cadence: BookClubSessionPlanner.cadence(for: session, calendar: calendar),
            roster: roster,
            departedMembers: departed,
            rotateLeader: session.rotateLeader,
            notes: session.notes,
            readings: BookClubSessionPlanner.readings(packetItems: readings, meetings: session.orderedMeetings)
        )
    }

    private func meeting(_ ordinal: Int, of session: CDBookClubSession) throws -> CDBookClubMeeting {
        try #require(session.orderedMeetings.first { $0.ordinal == Int32(ordinal) && !$0.isDeleted })
    }

    // MARK: - Save

    @Test("Saving a renamed session keeps every meeting, its held mark and its leader")
    func renameKeepsMeetings() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let roster = [UUID(), UUID()]
        let session = try seedSession(roster: roster, in: context)
        let first = try meeting(1, of: session)
        first.markCompleted(true)
        let reassigned = UUID()
        first.leaderStudentID = reassigned.uuidString
        let firstID = first.objectID
        let completedAt = first.completedAt
        #expect(CoreDataTestHelpers.save(context))

        var change = edits(for: session, roster: roster)
        change.displayName = "Charlotte's Web"
        BookClubSessionPlanner.applyEdits(
            change, to: session, today: try day(2026, 9, 20), calendar: calendar, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        #expect(session.displayName == "Charlotte's Web")
        #expect(session.orderedMeetings.count == 4)
        let kept = try meeting(1, of: session)
        #expect(kept.objectID == firstID)
        #expect(kept.isCompleted)
        #expect(kept.completedAt == completedAt)
        #expect(kept.leaderStudentID == reassigned.uuidString)
    }

    @Test("A schedule change rebuilds only the meetings not yet held, none in the past")
    func scheduleChangeKeepsHeldMeetings() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let roster = [UUID(), UUID()]
        let session = try seedSession(roster: roster, in: context)
        try meeting(1, of: session).markCompleted(true)
        try meeting(2, of: session).markCompleted(true)
        let heldDates = try [meeting(1, of: session).date, meeting(2, of: session).date]
        #expect(CoreDataTestHelpers.save(context))

        let today = try day(2026, 10, 7) // a Wednesday, after both held meetings
        var change = edits(for: session, roster: roster)
        change.cadenceKind = .biweekly
        change.cadence = .biweekly(weekday: 2)
        BookClubSessionPlanner.applyEdits(change, to: session, today: today, calendar: calendar, context: context)
        #expect(CoreDataTestHelpers.save(context))

        let meetings = session.orderedMeetings
        #expect(meetings.map(\.ordinal) == [1, 2, 3, 4])
        #expect(try [meeting(1, of: session).date, meeting(2, of: session).date] == heldDates)
        #expect(try meeting(1, of: session).isCompleted)
        #expect(try meeting(2, of: session).isCompleted)
        let rebuilt = try [meeting(3, of: session), meeting(4, of: session)]
        #expect(rebuilt.allSatisfy { ($0.date ?? .distantPast) >= today })
        #expect(rebuilt.map(\.readingLabel) == [readings[2].label, readings[3].label])
        #expect(try rebuilt[0].date == day(2026, 10, 12))
        #expect(try rebuilt[1].date == day(2026, 10, 26))
        #expect(session.endDate == rebuilt[1].date)
    }

    @Test("An edited reading label reaches its meeting, held or not, without rebuilding")
    func labelEditInPlace() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let roster = [UUID()]
        let session = try seedSession(roster: roster, in: context)
        try meeting(1, of: session).markCompleted(true)
        let unheldID = try meeting(2, of: session).objectID
        #expect(CoreDataTestHelpers.save(context))

        var change = edits(for: session, roster: roster)
        change.readings[0].label = "Prologue and Chapter 1"
        change.readings[1].label = "Chapters 2–4"
        BookClubSessionPlanner.applyEdits(
            change, to: session, today: try day(2026, 9, 20), calendar: calendar, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        #expect(try meeting(1, of: session).readingLabel == "Prologue and Chapter 1")
        #expect(try meeting(1, of: session).isCompleted)
        #expect(try meeting(2, of: session).readingLabel == "Chapters 2–4")
        #expect(try meeting(2, of: session).objectID == unheldID)
    }

    @Test("A child who left stays on the session but leads no new meeting")
    func departedMemberKept() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID()
        let etty = UUID()
        let session = try seedSession(roster: [maya, etty], in: context)

        let change = edits(for: session, roster: [etty], departed: [maya])
        BookClubSessionPlanner.applyEdits(
            change, to: session, today: try day(2026, 9, 1), calendar: calendar, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        #expect(session.studentIDs == [etty, maya])
        #expect(session.orderedMeetings.allSatisfy { $0.leaderStudentID == etty.uuidString })
    }

    // MARK: - Regenerate

    @Test("Regenerate gives each unmet reading one meeting, after the last held one and not before today")
    func regenerateByReading() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let roster = [UUID(), UUID()]
        let session = try seedSession(roster: roster, in: context)
        // Readings 1 and 3 held, not the first two; and a stray second meeting
        // for reading 3, as the old count-based Regenerate could leave.
        try meeting(1, of: session).markCompleted(true)
        let third = try meeting(3, of: session)
        third.markCompleted(true)
        let stray = CDBookClubMeeting(context: context)
        stray.session = session
        stray.ordinal = 3
        stray.readingLabel = readings[2].label
        stray.date = try day(2026, 9, 28)
        #expect(CoreDataTestHelpers.save(context))

        let today = try day(2026, 9, 16)
        let meetings = session.orderedMeetings
        let start = BookClubSessionPlanner.regenerationStart(today: today, meetings: meetings, calendar: calendar)
        // The last held meeting is reading 3 on Sept 21, so the next may fall from Sept 22.
        #expect(try start == day(2026, 9, 22))

        BookClubSessionPlanner.regenerateUnheldMeetings(
            of: session,
            schedule: BookClubSessionPlanner.Schedule(
                readings: BookClubSessionPlanner.readings(packetItems: readings, meetings: meetings),
                start: start,
                cadence: BookClubSessionPlanner.cadence(for: session, calendar: calendar),
                roster: roster,
                rotateLeader: true
            ),
            calendar: calendar,
            context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let after = session.orderedMeetings
        #expect(after.map(\.ordinal).sorted() == [1, 2, 3, 4])
        #expect(try meeting(1, of: session).isCompleted)
        #expect(try meeting(3, of: session).objectID == third.objectID)
        let rebuilt = try [meeting(2, of: session), meeting(4, of: session)]
        #expect(rebuilt.map(\.readingLabel) == [readings[1].label, readings[3].label])
        #expect(try rebuilt.map(\.date) == [day(2026, 9, 28), day(2026, 10, 5)])
        // Leaders rotate by reading, as a fresh schedule's do.
        #expect(rebuilt.map(\.leaderStudentID) == [roster[1].uuidString, roster[1].uuidString])
    }

    @Test("Regenerate with nothing held starts today, not on the session's first day")
    func regenerateStartsToday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let session = try seedSession(roster: [], in: context)
        let today = try day(2026, 10, 10)
        #expect(
            BookClubSessionPlanner.regenerationStart(
                today: today, meetings: session.orderedMeetings, calendar: calendar
            ) == today
        )
    }

    // MARK: - Row wording

    @Test("The sessions list says when the next meeting is by day, not by hour")
    func nextMeetingWording() throws {
        let meetingDay = try day(2026, 10, 12)
        let morning = try #require(calendar.date(byAdding: .hour, value: 9, to: meetingDay))
        let row = BookClubSessionRowView.self
        #expect(row.nextMeetingText(for: meetingDay, now: morning, calendar: calendar) == "Next: today")
        let dayBefore = try day(2026, 10, 11)
        #expect(row.nextMeetingText(for: meetingDay, now: dayBefore, calendar: calendar) == "Next: tomorrow")
        let weekBefore = try day(2026, 10, 5)
        let inAWeek = row.nextMeetingText(for: meetingDay, now: weekBefore, calendar: calendar)
        #expect(inAWeek.hasPrefix("Next: in "))
        #expect(!inAWeek.contains("hour"))
    }
}
