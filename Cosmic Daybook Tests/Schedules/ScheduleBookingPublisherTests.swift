import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `ScheduleBookingPublisher`: one booking per planned lesson from today
/// through 13 days ahead, never written backwards, stale ones removed, and two
/// devices' copies folded only where that's safe.
@Suite("Schedules: the booking publisher", .serialized)
@MainActor
struct ScheduleBookingPublisherTests {

    private typealias Support = TimetableTestSupport
    private let today = Support.monday
    /// 7:00 on Monday 26 October.
    private var now: Date { Support.time(today, 7) }

    private func publisher(_ context: NSManagedObjectContext, at date: Date? = nil) -> ScheduleBookingPublisher {
        let moment = date ?? now
        return ScheduleBookingPublisher(context: context, importsExpected: false, now: { moment })
    }

    private func at(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
    }

    /// A presentation planned for `moment` (nil: not scheduled), last changed at `modified`.
    @discardableResult
    private func plan(
        _ moment: Date?,
        _ children: [String] = [Support.lucy],
        modified: Date? = nil,
        in context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let presentation = CDLessonAssignment(context: context)
        presentation.lessonID = UUID().uuidString
        presentation.lessonTitleSnapshot = "A lesson's name"
        if let moment { presentation.schedule(for: moment) }
        presentation.studentIDs = children
        presentation.modifiedAt = modified ?? at(-3600)
        return presentation
    }

    @discardableResult
    private func booking(
        for presentationID: UUID?,
        day: Date,
        source: Date?,
        created: Date,
        modified: Date? = nil,
        id: UUID = UUID(),
        in context: NSManagedObjectContext
    ) -> CDTimetableBooking {
        let booking = CDTimetableBooking(context: context)
        booking.id = id
        booking.presentationID = presentationID?.uuidString ?? UUID().uuidString
        booking.day = day
        booking.studentIDs = [Support.lucy]
        booking.sourceModifiedAt = source
        booking.createdAt = created
        booking.modifiedAt = modified ?? created
        return booking
    }

    private func bookings(_ context: NSManagedObjectContext) -> [CDTimetableBooking] {
        context.safeFetch(CDFetchRequest(CDTimetableBooking.self))
    }

    private func booking(
        of presentation: CDLessonAssignment, in context: NSManagedObjectContext
    ) -> CDTimetableBooking? {
        bookings(context).first { $0.presentationID == presentation.id?.uuidString }
    }

    // MARK: - The window

    @Test("Today through 13 days ahead, scheduled and not given, with the half, time, order and children")
    func window() async throws {
        let context = try Support.context()
        let first = plan(Support.time(today, 9), [Support.ari, Support.bea], in: context)
        let second = plan(Support.time(today, 9, 0, second: 1), in: context)
        let setTime = plan(Support.time(today, 10, 30), in: context)
        let afternoon = plan(Support.time(today, 14), in: context)
        let lastDay = plan(Support.time(Support.day(2026, 11, 8), 9), in: context)
        let pastWindow = plan(Support.time(Support.day(2026, 11, 9), 9), in: context)
        let yesterday = plan(Support.time(Support.day(2026, 10, 25), 9), in: context)
        let given = plan(Support.time(today, 11, 15), in: context)
        given.markPresented(at: Support.time(today, 6))
        let unscheduled = plan(nil, in: context)
        #expect(context.safeSave())

        let outcome = try #require(await publisher(context).publish())
        #expect(outcome.inserted == 5)
        #expect(bookings(context).count == 5)
        for missing in [pastWindow, yesterday, given, unscheduled] {
            #expect(booking(of: missing, in: context) == nil)
        }

        let firstBooking = try #require(booking(of: first, in: context))
        #expect(firstBooking.day == today)
        #expect(firstBooking.half == .morning)
        #expect(firstBooking.setMinute == nil)
        #expect(firstBooking.minute == -1)
        #expect(firstBooking.order == 0)
        #expect(firstBooking.studentIDs == [Support.ari, Support.bea])
        #expect(firstBooking.sourceModifiedAt == first.modifiedAt)
        #expect(try #require(booking(of: second, in: context)).order == 1)
        let timed = try #require(booking(of: setTime, in: context))
        #expect(timed.setMinute == Support.minutes(10, 30))
        #expect(timed.order == 2, "a half's order counts its timed lessons too")
        let afternoonBooking = try #require(booking(of: afternoon, in: context))
        #expect(afternoonBooking.half == .afternoon)
        #expect(afternoonBooking.order == 0)
        #expect(try #require(booking(of: lastDay, in: context)).day == Support.day(2026, 11, 8))

        // A second run with nothing new writes nothing.
        let again = try #require(await publisher(context).publish())
        #expect(again == ScheduleBookingPublisher.Outcome())
        #expect(!context.hasChanges)
    }

    @Test("A booking reads as a lesson with no title")
    func bookingsCarryNoTitle() async throws {
        let context = try Support.context()
        plan(Support.time(today, 10, 30), [Support.ari], in: context)
        #expect(context.safeSave())
        await publisher(context).publish()
        let read = try #require(bookings(context).first.flatMap(ScheduleLessonSnapshot.init(booking:)))
        #expect(read.title == nil)
        #expect(read.minute == Support.minutes(10, 30))
        #expect(read.studentIDs == [Support.ari])
    }

    // MARK: - Never backwards

    @Test("A booking is never written back to an older plan; a newer one, or the same with other children, is")
    func neverBackwards() async throws {
        let context = try Support.context()
        let presentation = plan(Support.time(today, 9), modified: at(-600), in: context)
        let id = try #require(presentation.id)
        // Another device booked a newer plan: Wednesday, by a change this device hasn't seen.
        let row = booking(for: id, day: Support.wednesday, source: at(-60), created: at(-60), in: context)
        #expect(context.safeSave())

        let behind = try #require(await publisher(context).publish())
        #expect(behind.updated == 0)
        #expect(row.day == Support.wednesday, "this device is behind: left alone")

        // This device catches up to a still newer plan.
        presentation.modifiedAt = at(-30)
        #expect(context.safeSave())
        let newer = try #require(await publisher(context).publish())
        #expect(newer.updated == 1)
        #expect(row.day == today)
        #expect(row.sourceModifiedAt == presentation.modifiedAt)

        // Same modifiedAt, other children (a roster edit that left the date alone).
        presentation.studentIDs = [Support.lucy, Support.ari]
        #expect(context.safeSave())
        let roster = try #require(await publisher(context).publish())
        #expect(roster.updated == 1)
        #expect(row.studentIDs == [Support.lucy, Support.ari])
    }

    // MARK: - Removing

    @Test("Removed: a past day, a lesson given, unscheduled or moved away, an unknown one over an hour old")
    func removals() async throws {
        let context = try Support.context()
        let pastDay = booking(
            for: UUID(), day: Support.day(2026, 10, 23), source: at(-7200), created: at(-60), in: context
        )
        let given = plan(Support.time(today, 9), modified: at(-60), in: context)
        given.markPresented(at: at(-120))
        given.modifiedAt = at(-60)
        let givenRow = booking(for: given.id, day: today, source: at(-3600), created: at(-3600), in: context)
        let unscheduled = plan(nil, modified: at(-60), in: context)
        let unscheduledRow = booking(
            for: unscheduled.id, day: today, source: at(-3600), created: at(-3600), in: context
        )
        let moved = plan(Support.time(Support.day(2026, 11, 20), 9), modified: at(-60), in: context)
        let movedRow = booking(for: moved.id, day: today, source: at(-3600), created: at(-3600), in: context)
        let behind = plan(nil, modified: at(-7200), in: context)
        let behindRow = booking(for: behind.id, day: today, source: at(-60), created: at(-60), in: context)
        let freshUnknown = booking(
            for: UUID(), day: today, source: at(-1800), created: at(-1800), in: context
        )
        let oldUnknown = booking(for: UUID(), day: today, source: at(-7200), created: at(-7200), in: context)
        #expect(context.safeSave())

        let outcome = try #require(await publisher(context).publish())
        #expect(outcome.removed == 5)
        for gone in [pastDay, givenRow, unscheduledRow, movedRow, oldUnknown] {
            #expect(gone.managedObjectContext == nil, "removed")
        }
        #expect(behindRow.managedObjectContext != nil, "this device knows an older plan than the booking's")
        #expect(freshUnknown.managedObjectContext != nil, "its lesson may still be on its way")
    }

    // MARK: - Doubles

    @Test("Two devices' bookings for one lesson fold into the one made first, with the newest values")
    func foldsDoubles() async throws {
        let context = try Support.context()
        let presentation = plan(Support.time(today, 9), modified: at(-60), in: context)
        let id = try #require(presentation.id)
        let first = booking(for: id, day: Support.tuesday, source: at(-600), created: at(-600), in: context)
        let second = booking(for: id, day: today, source: at(-60), created: at(-300), modified: at(-60), in: context)
        #expect(context.safeSave())
        #expect(CDTimetableBooking.newestPerPresentation([first, second]).first === second, "readers take the newest")

        let outcome = try #require(await publisher(context).publish())
        #expect(outcome.folded == 1)
        #expect(bookings(context).count == 1)
        #expect(first.managedObjectContext != nil, "the one made first stays")
        #expect(first.day == today, "with the newest values")
        #expect(second.managedObjectContext == nil)
    }

    @Test("A copy in another zone, one with no answer, and one with the kept one's id are never deleted")
    func foldIsZoneSafe() throws {
        let context = try Support.context()
        let id = UUID()
        let kept = booking(for: id, day: today, source: at(-60), created: at(-600), in: context)
        let sameZone = booking(for: id, day: today, source: at(-60), created: at(-500), in: context)
        let otherZone = booking(for: id, day: today, source: at(-60), created: at(-400), in: context)
        let unanswered = booking(for: id, day: today, source: at(-60), created: at(-300), in: context)
        let sameID = booking(
            for: id, day: today, source: at(-60), created: at(-200), id: try #require(kept.id), in: context
        )
        #expect(context.safeSave())

        let share = "com.apple.coredata.cloudkit.share.ABC"
        let zones = ClassroomNames.ZoneMap(
            asked: Set([kept, sameZone, otherZone, sameID].map(\.objectID)),
            zones: [
                kept.objectID: share, sameZone.objectID: share, otherZone.objectID: "com.apple.coredata.cloudkit.zone",
                sameID.objectID: share
            ]
        )
        let rows = [kept, sameZone, otherZone, unanswered, sameID]
        #expect(ScheduleBookingPublisher.fold(rows, zones: zones, in: context) == 1)
        #expect(sameZone.isDeleted)
        #expect(!kept.isDeleted && !otherZone.isDeleted && !unanswered.isDeleted && !sameID.isDeleted)
    }

    // MARK: - Waiting

    @Test("While the view context holds an unsaved edit, nothing is written")
    func waitsForUnsavedEdits() async throws {
        let context = try Support.context()
        let presentation = plan(Support.time(today, 9), in: context)
        #expect(context.safeSave())
        presentation.notes = "typing…"
        #expect(await publisher(context).publish() == nil)
        #expect(bookings(context).isEmpty)
        #expect(context.safeSave())
        #expect(await publisher(context).publish()?.inserted == 1)
    }
}
