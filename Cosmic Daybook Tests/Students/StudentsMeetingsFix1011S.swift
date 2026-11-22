import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, Students (#26–#34): finishing one child's meeting from
// a group booking, pinned notes past the first page, the Next Birthday sort,
// and the profile's attendance counts. The recall items (#26, #28, #32) went
// with Recall (2026-11-21).
@Suite("Students and meetings (bug hunt 2026-10-11)")
@MainActor
struct StudentsMeetingsFix1011STests {

    // MARK: - Group bookings (#27)

    private func bookings(_ context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        context.safeFetch(CDFetchRequest(CDScheduledMeeting.self))
    }

    @Test("Completing one child's meeting takes only her off the group booking")
    func completeBookingLeavesTheRestOfTheGroup() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), eli = UUID(), ora = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(participantIDs: [maya, eli, ora], date: today, context: context)

        let bookedFor = MeetingScheduler.completeBooking(studentID: maya, heldOn: Date(), context: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(bookedFor == today)
        let group = try #require(bookings(context).first)
        #expect(bookings(context).count == 1)
        #expect(group.participantStudentIDs == [eli.uuidString, ora.uuidString])
        // A group stores its first participant in studentID; it follows.
        #expect(group.studentID == eli.uuidString)
    }

    @Test("The booking goes once the last child in it has met")
    func completeBookingDeletesAnEmptyGroup() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), eli = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(participantIDs: [maya, eli], date: today, context: context)

        _ = MeetingScheduler.completeBooking(studentID: maya, heldOn: Date(), context: context)
        _ = MeetingScheduler.completeBooking(studentID: eli, heldOn: Date(), context: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(bookings(context).isEmpty)
    }

    // Guard: passes on the old code too.
    @Test("A later group booking stays whole when she meets today")
    func completeBookingLeavesALaterGroup() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), eli = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(
            participantIDs: [maya, eli], date: AppCalendar.addingDays(7, to: today), context: context
        )

        #expect(MeetingScheduler.completeBooking(studentID: maya, heldOn: Date(), context: context) == nil)
        #expect(try #require(bookings(context).first).participantStudentIDs == [maya.uuidString, eli.uuidString])
    }

    @Test("Today's Complete on a group booking keeps it for the children not yet met")
    func todayCompleteKeepsTheRest() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), eli = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(participantIDs: [maya, eli], date: today, context: context)
        let meetingID = try #require(bookings(context).first?.id)

        // The session files the meeting (completeBooking), then Today clears
        // the booking it was opened from.
        _ = MeetingScheduler.completeBooking(studentID: eli, heldOn: Date(), context: context)
        #expect(CoreDataTestHelpers.save(context))
        MeetingScheduler.clearMeeting(id: meetingID, completedFor: eli, context: context)

        let left = bookings(context)
        #expect(left.count == 1)
        #expect(left.first?.participantStudentIDs == [maya.uuidString])
        #expect(!context.hasChanges)
    }

    // Guard: passes on the old code too.
    @Test("Today's Complete on an individual booking deletes it")
    func todayCompleteDeletesAnIndividualBooking() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID()
        MeetingScheduler.scheduleMeeting(studentID: maya, date: Date(), context: context)
        let meetingID = try #require(bookings(context).first?.id)

        MeetingScheduler.clearMeeting(id: meetingID, completedFor: maya, context: context)

        #expect(bookings(context).isEmpty)
    }

    // MARK: - Pinned notes (#29)

    private func note(daysAgo: Int, pinned: Bool = false) -> UnifiedNoteItem {
        UnifiedNoteItem(
            id: UUID(), date: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400), body: "Note \(daysAgo)",
            source: .general, contextText: "", color: .gray, associatedID: nil, tags: [],
            includeInReport: false, needsFollowUp: false, imagePath: nil, reportedBy: nil,
            reporterName: nil, isPinned: pinned
        )
    }

    @Test("A pinned note stays in Pinned however many newer notes there are")
    func pinnedFromTheWholeList() {
        let newer = (0..<40).map { note(daysAgo: $0) }
        let pinnedOld = note(daysAgo: 100, pinned: true)
        let all = newer + [pinnedOld]

        let items = StudentNotesTimelineList.DisplayedItems.make(
            from: all, displayedCount: 30, calendar: AppCalendar.shared
        )

        #expect(items.pinned.map(\.id) == [pinnedOld.id])
        // The page holds 30 unpinned notes; ten more wait behind Show More.
        #expect(items.grouped.flatMap(\.items).count == 30)
        #expect(items.remainingCount == 10)
    }

    // MARK: - Next Birthday sort (#31)

    @Test("A child with no birthday sorts last by Next Birthday")
    func noBirthdaySortsLast() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let none = CoreDataTestHelpers.seedStudent(in: context, firstName: "Nobirthday")
        let soon = CoreDataTestHelpers.seedStudent(in: context, firstName: "Soon")
        let today = try CoreDataTestHelpers.day("2026-10-11")
        soon.birthday = try CoreDataTestHelpers.day("2016-10-20")
        none.birthday = nil
        #expect(CoreDataTestHelpers.save(context))

        let sorted = StudentsViewModel.filteredStudents([none, soon], filter: .all, sortOrder: .birthday, today: today)

        #expect(sorted.map(\.firstName) == ["Soon", "Nobirthday"])
    }

    // MARK: - Profile attendance (#34)

    @Test("The profile counts a duplicated day once and a late arrival who left early as tardy")
    func profileAttendanceCounts() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ora = UUID()
        let reference = try CoreDataTestHelpers.day("2026-10-15")
        let start = FloridaGradeCalculator.schoolYearStart(for: reference, calendar: AppCalendar.shared)
        func day(_ offset: Int) -> Date { AppCalendar.addingDays(offset, to: start) }
        func mark(_ status: AttendanceStatus, _ offset: Int) -> CDAttendanceRecord {
            let record = CoreDataTestHelpers.seedAttendance(in: context, studentID: ora, date: day(offset))
            record.status = status
            return record
        }
        // Two devices marked day 3 tardy before syncing: one late day.
        _ = mark(.tardy, 3)
        _ = mark(.tardy, 3)
        // Absent twice on day 5 the same way: one absence.
        _ = mark(.absent, 5)
        _ = mark(.absent, 5)
        // Came late on day 8, then left early: still late that day.
        let lateThenLeft = mark(.leftEarly, 8)
        lateThenLeft.statusBeforeLeavingRaw = AttendanceStatus.tardy.rawValue
        // On time on day 9, then left early: not late.
        let onTimeThenLeft = mark(.leftEarly, 9)
        onTimeThenLeft.statusBeforeLeavingRaw = AttendanceStatus.present.rawValue
        #expect(CoreDataTestHelpers.save(context))

        let counts = try AttendanceInfoRow.schoolYearCounts(studentID: ora, on: reference, in: context)

        #expect(counts == AttendanceInfoRow.SchoolYearCounts(tardy: 2, absent: 1))
    }
}
