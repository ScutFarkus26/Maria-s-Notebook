import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// An every-week or This Day and After edit reaches later days that have a
/// change of their own, field by field (plan "Domain logic fixes", R15), and
/// a child leaving the class is taken out of every group from a day on (R7).
@Suite("Schedules: edits reaching later days' changes", .serialized)
@MainActor
struct TimetableCarryEditTests {

    private typealias Support = TimetableTestSupport
    private let now = Support.time(TimetableTestSupport.monday, 8)
    private let lucy = Support.lucy
    private let ari = Support.ari
    private let bea = Support.bea

    private func reading(children: [String]) -> TimetableBlockValues {
        TimetableBlockValues(startMinute: Support.minutes(9, 15), lengthMinutes: 30, title: "Reading",
                             studentIDs: children)
    }

    private struct Fixture {
        let context: NSManagedObjectContext
        let lane: CDTimetableLane
        let block: CDTimetableBlock
    }

    /// Morah Devora's lane with a weekly Monday Reading group for `children`.
    private func setUp(children: [String]) throws -> Fixture {
        let context = try Support.context()
        let lane = TimetableService.addPerson(named: "Morah Devora", in: context, now: now)
        let block = try #require(TimetableService.addBlock(
            reading(children: children), to: lane, on: [.monday], from: Support.lastMonday, in: context, now: now
        ).first)
        #expect(context.safeSave())
        return Fixture(context: context, lane: lane, block: block)
    }

    /// The Reading block as `day` shows it, from the store.
    private func shown(_ day: Date, _ context: NSManagedObjectContext) -> TimetableBlockValues? {
        let lane = Support.resolveStored(day, in: context).lanes.first { $0.lane.name == "Morah Devora" }
        return lane?.items.compactMap(\.block).first?.values
    }

    @Test("An every-week edit reaches a later week's one-day change that still has the old value")
    func everyWeekEditReachesLaterChange() throws {
        let fixture = try setUp(children: [lucy])
        let context = fixture.context, block = fixture.block
        // Next Monday only, Reading moves to 10:00.
        TimetableService.edit(
            block, applying: TimetableService.BlockEdit(startMinute: Support.minutes(10)), scope: .onlyThisDay,
            on: Support.nextMonday, in: context, now: now
        )
        #expect(context.safeSave())

        // Danny adds Ari every week, from this Monday.
        TimetableService.edit(
            block, applying: TimetableService.BlockEdit(studentIDs: [lucy, ari]), scope: .everyWeek,
            on: Support.monday, in: context, now: now
        )
        #expect(context.safeSave())
        #expect(shown(Support.monday, context)?.studentIDs == [lucy, ari])
        #expect(shown(Support.nextMonday, context)?.studentIDs == [lucy, ari], "the later change gets Ari too")
        #expect(shown(Support.nextMonday, context)?.startMinute == Support.minutes(10), "and keeps its own time")
    }

    @Test("A This Day and After edit reaches later changes, and leaves a field a change set itself")
    func thisDayAndAfterReachesLaterChanges() throws {
        let fixture = try setUp(children: [lucy])
        let context = fixture.context, block = fixture.block
        // Next Monday has its own children (Bea instead) and its own time.
        TimetableService.edit(
            block, applying: TimetableService.BlockEdit(startMinute: Support.minutes(10), studentIDs: [bea]),
            scope: .onlyThisDay, on: Support.nextMonday, in: context, now: now
        )
        #expect(context.safeSave())

        // From this Monday on: renamed, and Ari added.
        let copy = TimetableService.edit(
            block, applying: TimetableService.BlockEdit(title: "Reading group", studentIDs: [lucy, ari]),
            scope: .thisDayAndAfter, on: Support.monday, in: context, now: now
        )
        #expect(context.safeSave())
        #expect(copy !== block)
        #expect(shown(Support.lastMonday, context) == reading(children: [lucy]))
        let later = try #require(shown(Support.nextMonday, context))
        #expect(later.title == "Reading group", "the title was the old one: it follows the edit")
        #expect(later.studentIDs == [bea], "the day's own children stay")
        #expect(later.startMinute == Support.minutes(10))
    }

    @Test("Taking a child out of the groups from a day on keeps her in earlier weeks, and runs once")
    func takeOutOfGroupsFromADay() throws {
        let fixture = try setUp(children: [lucy, ari])
        let context = fixture.context, lane = fixture.lane, block = fixture.block
        // Next Monday's change has her too, and so does a one-off that day.
        TimetableService.edit(
            block, applying: TimetableService.BlockEdit(startMinute: Support.minutes(10)), scope: .onlyThisDay,
            on: Support.nextMonday, in: context, now: now
        )
        TimetableService.addOneOff(
            TimetableBlockValues(startMinute: Support.minutes(13), lengthMinutes: 30, title: "Trip",
                                 studentIDs: [ari, lucy]),
            to: lane, on: Support.nextMonday, in: context, now: now
        )
        #expect(context.safeSave())

        let changed = TimetableService.takeOutOfGroups(
            studentID: lucy.lowercased(), from: Support.monday, in: context, now: now
        )
        #expect(changed == 3)
        #expect(context.safeSave())
        #expect(shown(Support.lastMonday, context)?.studentIDs == [lucy, ari])
        #expect(shown(Support.monday, context)?.studentIDs == [ari])
        #expect(shown(Support.nextMonday, context)?.studentIDs == [ari])
        #expect(shown(Support.nextMonday, context)?.startMinute == Support.minutes(10))
        let oneOff = Support.resolveStored(Support.nextMonday, in: context).lanes
            .flatMap(\.items).compactMap(\.block).first { $0.isOneOff }
        #expect(oneOff?.values.studentIDs == [ari])
        #expect(TimetableService.takeOutOfGroups(studentID: lucy, from: Support.monday, in: context, now: now) == 0)
    }
}
