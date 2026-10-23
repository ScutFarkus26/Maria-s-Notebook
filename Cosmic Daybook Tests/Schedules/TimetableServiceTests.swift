import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `TimetableService`, the only writer: the starter lanes, blocks on several
/// weekdays, the three edit scopes across weeks, deleting, one-offs, Out
/// Today, undo, copying a day, and replacing a week. Each is read back through
/// the resolver, as the screens read it.
@Suite("Schedules: the timetable service", .serialized)
@MainActor
struct TimetableServiceTests {

    private typealias Support = TimetableTestSupport
    private let now = Support.time(TimetableTestSupport.monday, 8)

    private func values(_ hour: Int, _ minute: Int = 0, _ length: Int = 60, _ title: String) -> TimetableBlockValues {
        TimetableBlockValues(startMinute: Support.minutes(hour, minute), lengthMinutes: length, title: title)
    }

    private func titles(_ lane: String, _ day: Date, _ context: NSManagedObjectContext) -> [String] {
        Support.storedTitles(lane, on: day, in: context)
    }

    @Test("The starter lanes: our class, the adolescent room and the guide's own; made once")
    func starterLanes() throws {
        let context = try Support.context()
        let lanes = TimetableService.makeStarterLanes(in: context, now: now)
        #expect(lanes.map(\.kind) == [.room, .room, .person])
        #expect(lanes.map(\.name).prefix(2) == ["Our class", "Adolescent room"])
        #expect(lanes.map(\.isGuide) == [false, false, true])
        #expect(lanes.map(\.sortOrder) == [0, 1, 2])
        let guideName = lanes.last?.name ?? ""
        #expect(!guideName.isEmpty)
        let devora = TimetableService.addPerson(named: "  Morah Devora ", in: context, now: now)
        #expect(devora.name == "Morah Devora")
        #expect(devora.kind == .person)
        #expect(devora.sortOrder == 3)
        #expect(context.safeSave())

        let again = TimetableService.makeStarterLanes(in: context, now: now)
        #expect(again.count == 4, "with lanes there it makes none")
        #expect(context.safeFetch(CDFetchRequest(CDTimetableLane.self)).count == 4)
    }

    @Test("Rename and reorder lanes; only what changed is written")
    func renameAndReorder() throws {
        let context = try Support.context()
        let lanes = TimetableService.makeStarterLanes(in: context, now: now)
        #expect(context.safeSave())
        let later = Support.time(Support.monday, 9)
        TimetableService.rename(lanes[1], to: "Adolescents", now: later)
        TimetableService.reorder([lanes[1], lanes[0], lanes[2]], now: later)
        #expect(lanes[1].name == "Adolescents")
        #expect(TimetableService.lanes(in: context).map(\.name).prefix(2) == ["Adolescents", "Our class"])
        #expect(lanes[2].modifiedAt == now, "the guide's lane kept its place")
        #expect(lanes[1].modifiedAt == later)
    }

    @Test("A block added on several weekdays is one block per day")
    func addOnSeveralWeekdays() throws {
        let context = try Support.context()
        let lane = TimetableService.addLane(named: "Our class", kind: .room, in: context, now: now)
        let blocks = TimetableService.addBlock(
            values(8, 30, 90, "Work cycle"), to: lane, on: [.monday, .tuesday, .monday], in: context, now: now
        )
        #expect(blocks.count == 2)
        #expect(Set(blocks.compactMap(\.weekday)) == [.monday, .tuesday])
        #expect(context.safeSave())
        #expect(titles("Our class", Support.monday, context) == ["Work cycle"])
        #expect(titles("Our class", Support.tuesday, context) == ["Work cycle"])
        #expect(titles("Our class", Support.wednesday, context).isEmpty)
    }

    @Test("Only This Day changes that date; the weeks around it are as before")
    func onlyThisDay() throws {
        let context = try Support.context()
        let lane = TimetableService.addLane(named: "Our class", kind: .room, in: context, now: now)
        let block = try #require(TimetableService.addBlock(
            values(9, 0, 60, "Math"), to: lane, on: [.monday], in: context, now: now
        ).first)
        let edited = TimetableService.edit(
            block, to: values(10, 0, 30, "Math games"), scope: .onlyThisDay, on: Support.monday, in: context, now: now
        )
        #expect(edited === block)
        #expect(context.safeSave())
        #expect(titles("Our class", Support.monday, context) == ["Math games"])
        #expect(titles("Our class", Support.lastMonday, context) == ["Math"])
        #expect(titles("Our class", Support.nextMonday, context) == ["Math"])
        #expect(Support.resolveStored(Support.monday, in: context).changeCount == 1)

        // Editing that day again updates the one change; back to the block's own values takes it away.
        TimetableService.edit(
            block, to: values(10, 0, 45, "Math games"), scope: .onlyThisDay, on: Support.monday, in: context, now: now
        )
        #expect(TimetableService.changes(of: block, on: Support.monday, in: context).count == 1)
        TimetableService.edit(
            block, to: block.values, scope: .onlyThisDay, on: Support.monday, in: context, now: now
        )
        #expect(context.safeSave())
        #expect(TimetableService.changes(of: block, on: Support.monday, in: context).isEmpty)
        #expect(titles("Our class", Support.monday, context) == ["Math"])
    }

    @Test("This Day and After ends the block the day before and starts a copy; earlier weeks keep the old values")
    func thisDayAndAfter() throws {
        let context = try Support.context()
        let lane = TimetableService.addLane(named: "Our class", kind: .room, in: context, now: now)
        let block = try #require(TimetableService.addBlock(
            values(9, 0, 60, "Math"), to: lane, on: [.monday], in: context, now: now
        ).first)
        // A change on the split day, and a cancel the Monday after.
        TimetableService.edit(
            block, to: values(9, 30, 60, "Math late"), scope: .onlyThisDay, on: Support.monday, in: context, now: now
        )
        TimetableService.cancel(block, on: Support.nextMonday, in: context, now: now)
        #expect(context.safeSave())

        let copy = TimetableService.edit(
            block, to: values(9, 0, 45, "Numbers"), scope: .thisDayAndAfter, on: Support.monday, in: context, now: now
        )
        #expect(copy !== block)
        #expect(context.safeSave())
        #expect(block.validUntil == Support.day(2026, 10, 25))
        #expect(copy.validFrom == Support.monday)
        #expect(titles("Our class", Support.lastMonday, context) == ["Math"])
        #expect(titles("Our class", Support.monday, context) == ["Numbers"], "the day's own change went")
        #expect(titles("Our class", Support.nextMonday, context).isEmpty, "the later cancel moved to the copy")
        #expect(titles("Our class", Support.day(2026, 11, 9), context) == ["Numbers"])
        #expect(TimetableService.changes(of: copy, on: Support.nextMonday, in: context).first?.kind == .cancelled)

        // From the copy's own first day, it's edited in place.
        let same = TimetableService.edit(
            copy, to: values(9, 0, 45, "Number work"), scope: .thisDayAndAfter, on: Support.monday,
            in: context, now: now
        )
        #expect(same === copy)
        #expect(context.safeFetch(CDFetchRequest(CDTimetableBlock.self)).count == 2)
    }

    @Test("Every week edits the block itself, past weeks included")
    func everyWeek() throws {
        let context = try Support.context()
        let lane = TimetableService.addLane(named: "Our class", kind: .room, in: context, now: now)
        let block = try #require(TimetableService.addBlock(
            values(9, 0, 60, "Math"), to: lane, on: [.monday], in: context, now: now
        ).first)
        let edited = TimetableService.edit(
            block, to: values(9, 0, 60, "Mathematics"), scope: .everyWeek, on: Support.monday, in: context, now: now
        )
        #expect(edited === block)
        #expect(context.safeSave())
        #expect(titles("Our class", Support.lastMonday, context) == ["Mathematics"])
        #expect(titles("Our class", Support.nextMonday, context) == ["Mathematics"])
        #expect(context.safeFetch(CDFetchRequest(CDTimetableBlock.self)).count == 1)
    }

    @Test("Deleting: that day only, from that day on, or every week from today; past weeks stay")
    func deleting() throws {
        let context = try Support.context()
        let lane = TimetableService.addLane(named: "Our class", kind: .room, in: context, now: now)
        let blocks = TimetableService.addBlock(
            values(9, 0, 60, "Math"), to: lane, on: [.monday, .tuesday, .wednesday], in: context, now: now
        )
        let monday = try #require(blocks.first { $0.weekday == .monday })
        let tuesday = try #require(blocks.first { $0.weekday == .tuesday })
        let wednesday = try #require(blocks.first { $0.weekday == .wednesday })

        TimetableService.delete(monday, scope: .onlyThisDay, on: Support.monday, in: context, now: now)
        // From next Tuesday on; this week's Tuesday stays.
        TimetableService.delete(tuesday, scope: .thisDayAndAfter, on: Support.day(2026, 11, 3), in: context, now: now)
        // Every week, ended from today (Monday the 26th): last week's Wednesday stays.
        TimetableService.delete(wednesday, scope: .everyWeek, on: Support.day(2026, 11, 4), in: context, now: now)
        #expect(context.safeSave())

        #expect(titles("Our class", Support.monday, context).isEmpty)
        #expect(titles("Our class", Support.nextMonday, context) == ["Math"])
        #expect(titles("Our class", Support.tuesday, context) == ["Math"])
        #expect(titles("Our class", Support.day(2026, 11, 3), context).isEmpty)
        #expect(titles("Our class", Support.day(2026, 10, 21), context) == ["Math"], "last week's Wednesday")
        #expect(titles("Our class", Support.wednesday, context).isEmpty)
        #expect(context.safeFetch(CDFetchRequest(CDTimetableBlock.self)).count == 3, "ended, not erased")

        // A block that hasn't begun yet is deleted outright, with its changes.
        let future = try #require(TimetableService.addBlock(
            values(13, 0, 30, "Art"), to: lane, on: [.thursday], from: Support.day(2026, 11, 5), in: context, now: now
        ).first)
        TimetableService.cancel(future, on: Support.day(2026, 11, 12), in: context, now: now)
        TimetableService.delete(future, scope: .everyWeek, on: Support.monday, in: context, now: now)
        #expect(context.safeSave())
        #expect(future.isDeleted || future.managedObjectContext == nil)
        let changes = context.safeFetch(CDFetchRequest(CDTimetableChange.self))
        #expect(changes.allSatisfy { $0.blockID != future.id?.uuidString })
    }

    @Test("A one-off is on its day only; cancelling it deletes it")
    func oneOff() throws {
        let context = try Support.context()
        let lane = TimetableService.addLane(named: "Our class", kind: .room, in: context, now: now)
        let assembly = try #require(TimetableService.addOneOff(
            values(13, 0, 30, "Assembly"), to: lane, on: Support.time(Support.tuesday, 15), in: context, now: now
        ))
        #expect(assembly.onDay == Support.tuesday)
        #expect(assembly.weekday == nil)
        #expect(context.safeSave())
        #expect(titles("Our class", Support.tuesday, context) == ["Assembly"])
        #expect(titles("Our class", Support.day(2026, 11, 3), context).isEmpty)
        #expect(Support.resolveStored(Support.tuesday, in: context).changeCount == 1)

        TimetableService.cancel(assembly, on: Support.tuesday, in: context, now: now)
        #expect(context.safeSave())
        #expect(titles("Our class", Support.tuesday, context).isEmpty)
        #expect(context.safeFetch(CDFetchRequest(CDTimetableBlock.self)).isEmpty)
    }

    @Test("Out Today and back in; undoing a day's changes")
    func outTodayAndUndo() throws {
        let context = try Support.context()
        let room = TimetableService.addLane(named: "Adolescent room", kind: .room, in: context, now: now)
        let devora = TimetableService.addPerson(named: "Morah Devora", in: context, now: now)
        let own = try #require(TimetableService.addBlock(
            values(9, 0, 45, "Chumash"), to: devora, on: [.monday], in: context, now: now
        ).first)
        var turnValues = values(10, 30, 75, "Navi")
        turnValues.teacherLaneID = devora.id
        TimetableService.addBlock(turnValues, to: room, on: [.monday], in: context, now: now)

        TimetableService.setOut(devora, true, on: Support.monday, in: context, now: now)
        TimetableService.setOut(devora, true, on: Support.monday, in: context, now: now)
        #expect(context.safeSave())
        #expect(TimetableService.isOut(devora, on: Support.monday, in: context))
        let changes = TimetableService.changes(from: Support.monday, through: Support.monday, in: context)
        #expect(changes.count == 1, "out once, however often it's tapped")
        let out = Support.resolveStored(Support.monday, in: context)
        #expect(out.lane(try #require(devora.id))?.isOut == true)
        #expect(titles("Morah Devora", Support.monday, context).isEmpty)
        #expect(out.lane(try #require(room.id))?.items.first?.block?.teacherIsOut == true)

        TimetableService.setOut(devora, false, on: Support.monday, in: context, now: now)
        #expect(context.safeSave())
        #expect(titles("Morah Devora", Support.monday, context) == ["Chumash", "Navi"])

        // Undo: a cancel and an out on the same day, both taken away.
        TimetableService.cancel(own, on: Support.monday, in: context, now: now)
        TimetableService.setOut(devora, true, on: Support.monday, in: context, now: now)
        #expect(context.safeSave())
        TimetableService.undoChanges(to: own, on: Support.monday, in: context)
        #expect(TimetableService.changes(of: own, on: Support.monday, in: context).isEmpty)
        TimetableService.undoAllChanges(on: Support.monday, in: context)
        #expect(context.safeSave())
        #expect(!Support.resolveStored(Support.monday, in: context).isChanged)
    }
}
