import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-29, #22: changing a Book Club's day or start date rebuilt
/// the meetings not yet held, and the rebuilt ones lost the leaders she had
/// picked by hand.
@Suite("Book Club schedule edits keep hand-picked leaders (fix 10-29 #22)")
@MainActor
struct BookClubScheduleEditLeadersFix1029Tests {

    private let calendar = Calendar(identifier: .gregorian)

    /// Thursday, October 29, 2026: before the session's first meeting.
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9)) ?? Date()
    }

    /// Four unheld Monday meetings from November 2, leaders rotating through
    /// `roster` unless `rotate` is off.
    private func seedSession(
        roster: [UUID], rotate: Bool, in context: NSManagedObjectContext
    ) throws -> CDBookClubSession {
        let session = CDBookClubSession(context: context)
        session.startDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))
        session.cadenceKind = .weekly
        session.meetingWeekdayMask = Int64(1) << 2
        session.studentIDs = roster
        session.rotateLeader = rotate
        for ordinal in 1...4 {
            let meeting = CDBookClubMeeting(context: context)
            meeting.session = session
            meeting.ordinal = Int32(ordinal)
            meeting.readingLabel = "Part \(ordinal)"
            meeting.date = calendar.date(byAdding: .day, value: 7 * (ordinal - 1), to: session.startDate ?? Date())
            meeting.leaderStudentID = rotate ? roster[(ordinal - 1) % roster.count].uuidString : ""
        }
        #expect(CoreDataTestHelpers.save(context))
        return session
    }

    /// The session moved to Wednesdays from November 4.
    private func movedToWednesday(
        _ session: CDBookClubSession, roster: [UUID], departed: [UUID] = []
    ) -> BookClubSessionPlanner.SessionEdits {
        BookClubSessionPlanner.SessionEdits(
            displayName: session.displayName,
            startDate: calendar.date(from: DateComponents(year: 2026, month: 11, day: 4)) ?? Date(),
            cadenceKind: .weekly,
            weekdayMask: Int64(1) << 4,
            cadence: .weekly(weekday: 4),
            roster: roster,
            departedMembers: departed,
            rotateLeader: session.rotateLeader,
            notes: session.notes,
            readings: BookClubSessionPlanner.readings(packetItems: [], meetings: session.orderedMeetings)
        )
    }

    private func leaders(_ session: CDBookClubSession) -> [String] {
        session.orderedMeetings.filter { !$0.isDeleted }.map(\.leaderStudentID)
    }

    @Test("With rotation off, a new day keeps every leader she picked")
    func rotationOffKeepsLeadersOnNewDay() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), etty = UUID()
        let session = try seedSession(roster: [maya, etty], rotate: false, in: context)
        session.orderedMeetings[0].leaderStudentID = etty.uuidString
        session.orderedMeetings[1].leaderStudentID = maya.uuidString
        #expect(CoreDataTestHelpers.save(context))

        BookClubSessionPlanner.applyEdits(
            movedToWednesday(session, roster: [maya, etty]),
            to: session, today: today, calendar: calendar, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let meetings = session.orderedMeetings.filter { !$0.isDeleted }
        // The meetings were rebuilt on Wednesdays…
        #expect(meetings.compactMap(\.date).allSatisfy { calendar.component(.weekday, from: $0) == 4 })
        // …and kept her leaders.
        #expect(leaders(session) == [etty.uuidString, maya.uuidString, "", ""])
    }

    @Test("With rotation on, a new day re-rotates only leaders the rotation picked")
    func rotationOnKeepsHandPickedOnNewDay() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), etty = UUID()
        let session = try seedSession(roster: [maya, etty], rotate: true, in: context)
        // Meeting 2 was rotated to Etty; the guide hand-picked Maya for it.
        session.orderedMeetings[1].leaderStudentID = maya.uuidString
        #expect(CoreDataTestHelpers.save(context))

        BookClubSessionPlanner.applyEdits(
            movedToWednesday(session, roster: [maya, etty]),
            to: session, today: today, calendar: calendar, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        #expect(leaders(session) == [maya.uuidString, maya.uuidString, maya.uuidString, etty.uuidString])
    }

    @Test("A hand-picked leader who has left isn't kept on a rebuilt meeting")
    func departedLeaderIsNotKept() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), etty = UUID()
        let session = try seedSession(roster: [maya, etty], rotate: false, in: context)
        session.orderedMeetings[0].leaderStudentID = etty.uuidString
        session.orderedMeetings[1].leaderStudentID = maya.uuidString
        #expect(CoreDataTestHelpers.save(context))

        BookClubSessionPlanner.applyEdits(
            movedToWednesday(session, roster: [maya], departed: [etty]),
            to: session, today: today, calendar: calendar, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        #expect(leaders(session) == ["", maya.uuidString, "", ""])
    }
}
