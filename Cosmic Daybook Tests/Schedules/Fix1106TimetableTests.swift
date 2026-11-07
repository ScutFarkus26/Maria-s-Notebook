import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-11-06 #16: a delete of a block that a This Day and After
/// edit split ends every piece of it, along a chain of splits and from
/// whichever piece is in view, and never a block that `replaceWeek` or
/// `copyDay` started where another ends.
@Suite("Fix 2026-11-06: deleting a split block", .serialized)
@MainActor
struct Fix1106TimetableTests {

    private typealias Support = TimetableTestSupport
    /// Monday 26 October 2026, 8:00.
    private let now = Support.time(TimetableTestSupport.monday, 8)
    private let nov2 = Support.day(2026, 11, 2)
    private let nov9 = Support.day(2026, 11, 9)
    private let nov16 = Support.day(2026, 11, 16)

    private func values(_ title: String, _ hour: Int = 9) -> TimetableBlockValues {
        TimetableBlockValues(startMinute: Support.minutes(hour), lengthMinutes: 60, title: title)
    }

    private func titles(_ day: Date, _ context: NSManagedObjectContext) -> [String] {
        Support.storedTitles("Our class", on: day, in: context)
    }

    private func mathOnMondays(_ context: NSManagedObjectContext) throws -> (CDTimetableLane, CDTimetableBlock) {
        let lane = TimetableService.addLane(named: "Our class", kind: .room, in: context, now: now)
        let block = try #require(TimetableService.addBlock(
            values("Math"), to: lane, on: [.monday], in: context, now: now
        ).first)
        #expect(context.safeSave())
        return (lane, block)
    }

    @Test("Every week, with an earlier day in view, also ends the copy a later This Day and After made")
    func everyWeekEndsTheSplitCopy() throws {
        let context = try Support.context()
        let (_, block) = try mathOnMondays(context)
        let copy = TimetableService.edit(
            block, to: values("Numbers"), scope: .thisDayAndAfter, on: nov9, in: context, now: now
        )
        #expect(copy !== block)
        #expect(context.safeSave())

        TimetableService.delete(block, scope: .everyWeek, on: nov2, in: context, now: now)
        #expect(context.safeSave())
        #expect(titles(Support.lastMonday, context) == ["Math"], "a past week still shows it")
        #expect(titles(Support.monday, context).isEmpty)
        #expect(titles(nov9, context).isEmpty, "the split's copy came back from its day on")
        #expect(titles(nov16, context).isEmpty)
    }

    @Test("Every week from the copy's own day ends the piece before it too")
    func everyWeekFromTheCopy() throws {
        let context = try Support.context()
        let (_, block) = try mathOnMondays(context)
        let copy = TimetableService.edit(
            block, to: values("Numbers"), scope: .thisDayAndAfter, on: nov9, in: context, now: now
        )
        #expect(context.safeSave())

        TimetableService.delete(copy, scope: .everyWeek, on: nov9, in: context, now: now)
        #expect(context.safeSave())
        #expect(titles(Support.lastMonday, context) == ["Math"])
        #expect(titles(Support.monday, context).isEmpty, "the original showed until the split")
        #expect(titles(nov2, context).isEmpty)
        #expect(titles(nov9, context).isEmpty)
    }

    @Test("This Day and After follows a chain of splits, made in either order")
    func thisDayAndAfterFollowsTheChain() throws {
        let context = try Support.context()
        let (_, block) = try mathOnMondays(context)
        // Split from the 9th, then the original again from the 2nd: three pieces.
        let late = TimetableService.edit(
            block, to: values("Numbers"), scope: .thisDayAndAfter, on: nov9, in: context, now: now
        )
        let middle = TimetableService.edit(
            block, to: values("Math games"), scope: .thisDayAndAfter, on: nov2, in: context, now: now
        )
        // And the latest piece once more, from the 16th: a copy of a copy.
        TimetableService.edit(
            late, to: values("Number work"), scope: .thisDayAndAfter, on: nov16, in: context, now: now
        )
        #expect(context.safeSave())
        #expect(titles(nov2, context) == ["Math games"])
        #expect(titles(nov9, context) == ["Numbers"])
        #expect(titles(nov16, context) == ["Number work"])

        TimetableService.delete(middle, scope: .thisDayAndAfter, on: nov2, in: context, now: now)
        #expect(context.safeSave())
        #expect(titles(Support.monday, context) == ["Math"], "the week before the day stays")
        #expect(titles(nov2, context).isEmpty)
        #expect(titles(nov9, context).isEmpty)
        #expect(titles(nov16, context).isEmpty)
    }

    @Test("A week replaced from a later day (set_timetable) keeps its blocks when the old one is deleted")
    func replaceWeekIsLeftAlone() throws {
        let context = try Support.context()
        let (lane, block) = try mathOnMondays(context)
        TimetableService.replaceWeek(
            of: lane, with: [TimetableService.WeeklyBlock(weekday: .monday, values: values("Math"))],
            from: nov9, in: context, now: now
        )
        #expect(context.safeSave())
        #expect(titles(nov9, context) == ["Math"])

        // The old block, seen on an earlier day, deleted every week.
        TimetableService.delete(block, scope: .everyWeek, on: nov2, in: context, now: now)
        #expect(context.safeSave())
        #expect(titles(nov2, context).isEmpty)
        #expect(titles(nov9, context) == ["Math"], "the new week's block is another block")
        #expect(titles(nov16, context) == ["Math"])
    }

    @Test("A day copied onto where an ended block stopped keeps its copy when that block is deleted")
    func copyDayIsLeftAlone() throws {
        let context = try Support.context()
        let (lane, monday) = try mathOnMondays(context)
        // Monday's Math stops after the 1st; Tuesday's Art is copied to Monday from the 2nd.
        TimetableService.delete(monday, scope: .thisDayAndAfter, on: nov2, in: context, now: now)
        TimetableService.addBlock(values("Art", 13), to: lane, on: [.tuesday], in: context, now: now)
        TimetableService.copyDay(.tuesday, of: lane, to: [.monday], from: nov2, in: context, now: now)
        #expect(context.safeSave())
        #expect(titles(nov2, context) == ["Art"])

        TimetableService.delete(monday, scope: .everyWeek, on: Support.monday, in: context, now: now)
        #expect(context.safeSave())
        #expect(titles(Support.monday, context).isEmpty)
        #expect(titles(nov2, context) == ["Art"], "the copied day is another block")
    }

    @Test("A split's copy has the id worked out from its block and day, the same every time")
    func splitCopyIDIsStable() throws {
        let context = try Support.context()
        let (_, block) = try mathOnMondays(context)
        let blockID = try #require(block.id)
        let copy = TimetableService.edit(
            block, to: values("Numbers"), scope: .thisDayAndAfter, on: nov9, in: context, now: now
        )
        #expect(copy.id == TimetableService.splitCopyID(of: blockID, from: nov9))
        #expect(TimetableService.splitCopyID(of: blockID, from: nov9) != TimetableService.splitCopyID(
            of: blockID, from: nov16
        ))
        #expect(Set(TimetableService.splitFamily(of: copy, in: context).map(\.objectID))
            == [block.objectID, copy.objectID])
    }
}
