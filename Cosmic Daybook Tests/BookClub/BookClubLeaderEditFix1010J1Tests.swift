import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Review round of the 2026-10-10 fixes: editing a Book Club roster re-led
/// every meeting not yet held, clearing hand-picked leaders with rotation off
/// and overwriting them with rotation on.
@Suite("Book Club roster edits keep chosen leaders (fix 10-10 J1 review)")
@MainActor
struct BookClubLeaderEditFix1010J1Tests {

    private let calendar = Calendar(identifier: .gregorian)

    /// Four unheld meetings, leaders rotating through `roster` unless `rotate` is off.
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

    private func edits(
        _ session: CDBookClubSession, roster: [UUID], departed: [UUID] = []
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
            readings: BookClubSessionPlanner.readings(packetItems: [], meetings: session.orderedMeetings)
        )
    }

    private func leaders(_ session: CDBookClubSession) -> [String] {
        session.orderedMeetings.map(\.leaderStudentID)
    }

    @Test("With rotation off, adding a child keeps hand-picked leaders; one who left is cleared")
    func rotationOffKeepsChosenLeaders() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), etty = UUID(), ora = UUID()
        let session = try seedSession(roster: [maya, etty], rotate: false, in: context)
        let meetings = session.orderedMeetings
        meetings[0].leaderStudentID = etty.uuidString
        meetings[1].leaderStudentID = maya.uuidString
        #expect(CoreDataTestHelpers.save(context))

        BookClubSessionPlanner.applyEdits(
            edits(session, roster: [etty, ora], departed: [maya]),
            to: session, today: Date(), calendar: calendar, context: context
        )

        #expect(leaders(session) == [etty.uuidString, "", "", ""])
    }

    @Test("With rotation on, a roster change re-rotates only leaders the rotation picked")
    func rotationOnKeepsHandPicked() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), etty = UUID(), ora = UUID()
        let session = try seedSession(roster: [maya, etty], rotate: true, in: context)
        // Meeting 2 was rotated to Etty; the guide hand-picked Maya for it.
        session.orderedMeetings[1].leaderStudentID = maya.uuidString
        #expect(CoreDataTestHelpers.save(context))

        BookClubSessionPlanner.applyEdits(
            edits(session, roster: [maya, etty, ora]),
            to: session, today: Date(), calendar: calendar, context: context
        )

        // New rotation over three: Maya, Etty, Ora, Maya; meeting 2 keeps her pick.
        #expect(leaders(session) == [maya.uuidString, maya.uuidString, ora.uuidString, maya.uuidString])
    }
}
