import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `TimetableService.edit` on a day with a change of its own (the 2026-10-29
/// bug hunt): the edit reaches later weeks, the day's own change stays on its
/// day, and an edit that changes nothing writes nothing.
@Suite("Schedules: editing a changed day", .serialized)
@MainActor
struct TimetableServiceDayEditTests {

    private typealias Support = TimetableTestSupport
    private let now = Support.time(TimetableTestSupport.monday, 8)

    private func values(_ hour: Int, _ minute: Int = 0, _ length: Int = 60, _ title: String) -> TimetableBlockValues {
        TimetableBlockValues(startMinute: Support.minutes(hour, minute), lengthMinutes: length, title: title)
    }

    /// "9:00 Math 60": Our class's blocks on `day`, from the store.
    private func slots(_ day: Date, _ context: NSManagedObjectContext) -> [String] {
        let lane = Support.resolveStored(day, in: context).lanes.first { $0.lane.name == "Our class" }
        return (lane?.items ?? []).compactMap(\.block).map {
            "\(TimetableDay.clockText($0.values.startMinute)) \($0.values.title) \($0.values.lengthMinutes)"
        }
    }

    @Test("An edit from a changed day on keeps that day's change on its day, with the edit made to it")
    func editOnAChangedDay() throws {
        let context = try Support.context()
        let lane = TimetableService.addLane(named: "Our class", kind: .room, in: context, now: now)
        let block = try #require(TimetableService.addBlock(
            values(9, 0, 60, "Math"), to: lane, on: [.monday], in: context, now: now
        ).first)
        // This Monday only, Math is at 10:30.
        TimetableService.edit(
            block, to: values(10, 30, 60, "Math"), scope: .onlyThisDay, on: Support.monday, in: context, now: now
        )
        #expect(context.safeSave())

        // Danny renames it from that day on: later weeks keep 9:00, the day keeps 10:30.
        let copy = TimetableService.edit(
            block, applying: TimetableService.BlockEdit(title: "Mathematics"), scope: .thisDayAndAfter,
            on: Support.monday, in: context, now: now
        )
        #expect(copy !== block)
        #expect(context.safeSave())
        #expect(slots(Support.monday, context) == ["10:30 Mathematics 60"])
        #expect(slots(Support.nextMonday, context) == ["9:00 Mathematics 60"])
        #expect(slots(Support.lastMonday, context) == ["9:00 Math 60"])
        #expect(Support.resolveStored(Support.monday, in: context).changeCount == 1)

        // Every week takes the edit to the block and to the day's change alike.
        TimetableService.edit(
            copy, applying: TimetableService.BlockEdit(lengthMinutes: 45), scope: .everyWeek, on: Support.monday,
            in: context, now: now
        )
        #expect(context.safeSave())
        #expect(slots(Support.monday, context) == ["10:30 Mathematics 45"])
        #expect(slots(Support.nextMonday, context) == ["9:00 Mathematics 45"])

        // Putting a changed day back to every week's time takes its change away, and makes no copy.
        TimetableService.edit(
            copy, to: values(11, 0, 45, "Mathematics"), scope: .onlyThisDay, on: Support.nextMonday,
            in: context, now: now
        )
        let same = TimetableService.edit(
            copy, applying: TimetableService.BlockEdit(startMinute: Support.minutes(9)), scope: .thisDayAndAfter,
            on: Support.nextMonday, in: context, now: now
        )
        #expect(same === copy)
        #expect(context.safeSave())
        #expect(TimetableService.changes(of: copy, on: Support.nextMonday, in: context).isEmpty)
        #expect(slots(Support.nextMonday, context) == ["9:00 Mathematics 45"])
        #expect(context.safeFetch(CDFetchRequest(CDTimetableBlock.self)).count == 2)

        // An edit that changes nothing writes nothing.
        let before = copy.modifiedAt
        TimetableService.edit(
            copy, applying: TimetableService.BlockEdit(), scope: .onlyThisDay, on: Support.nextMonday,
            in: context, now: Support.time(Support.monday, 9)
        )
        #expect(!context.hasChanges)
        #expect(copy.modifiedAt == before)
    }
}
