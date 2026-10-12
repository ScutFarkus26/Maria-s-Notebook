import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review 2026-10-11 (a) #4: a group booking stays only for children still
// here, and what's left of one for a single child is her booking.
@Suite("Group bookings (review fixes 10-11)")
@MainActor
struct MeetingSchedulerFix1011MainTests {

    private func bookings(_ context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        context.safeFetch(CDFetchRequest(CDScheduledMeeting.self))
    }

    @Test("The booking goes when everyone left in it has left the class")
    func bookingGoesWhenOnlyDepartedChildrenRemain() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Park")
        eli.enrollmentStatus = .withdrawn
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(
            participantIDs: [try #require(maya.id), try #require(eli.id)], date: today, context: context
        )

        _ = MeetingScheduler.completeBooking(studentID: try #require(maya.id), heldOn: Date(), context: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(bookings(context).isEmpty)
    }

    @Test("A child not on this device yet keeps the booking")
    func unknownChildKeepsTheBooking() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let notSyncedYet = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(
            participantIDs: [try #require(maya.id), notSyncedYet], date: today, context: context
        )

        _ = MeetingScheduler.completeBooking(studentID: try #require(maya.id), heldOn: Date(), context: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(bookings(context).first?.participantStudentIDs == [notSyncedYet.uuidString])
    }

    @Test("Booking a child whose group has dwindled to her moves that booking, not a second one")
    func singleChildGroupIsHerBooking() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), eli = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(participantIDs: [maya, eli], date: today, context: context)
        _ = MeetingScheduler.completeBooking(studentID: maya, heldOn: Date(), context: context)

        let result = MeetingScheduler.bookMeeting(studentID: eli, date: today, context: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(result.outcome == .unchanged)
        #expect(bookings(context).count == 1)
    }
}
