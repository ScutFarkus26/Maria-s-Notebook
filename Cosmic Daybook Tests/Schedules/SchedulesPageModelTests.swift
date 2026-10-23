import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Plan - Schedules, Phase 2A: the Schedules page's model. First run, the
/// edits it makes through `TimetableService` (saved on the view context),
/// the Week view's days, and the warnings it words with the children's names.
/// Shared by the Schedules page suites.
@MainActor
enum SchedulesPageTestSupport {
    typealias Support = TimetableTestSupport

    /// A page on Monday 26 October 2026, "now" at 9:30 that morning.
    static func page(_ context: NSManagedObjectContext, day: Date = Support.monday) -> SchedulesPageModel {
        let saves = SaveCoordinator.preview
        let model = SchedulesPageModel(
            context: context, saveCoordinator: saves, day: day, calendar: Support.calendar,
            now: { Support.time(Support.monday, 9, 30) }
        )
        model.reload()
        return model
    }

    /// The page set up, with Morah Devora added: our class, the adolescent
    /// room, the guide, Morah Devora.
    static func setUpPage(_ context: NSManagedObjectContext) throws -> (SchedulesPageModel, [TimetableLaneSnapshot]) {
        let model = page(context)
        #expect(model.setUp())
        #expect(model.addPerson(named: "Morah Devora"))
        try #require(model.lanes.count == 4)
        return (model, model.lanes)
    }

    static func titles(_ lane: TimetableLaneSnapshot, in day: ScheduleDay) -> [String] {
        (day.lane(lane.id)?.items ?? []).compactMap { $0.block?.values.title }
    }
}

@Suite("Schedules page")
@MainActor
struct SchedulesPageModelTests {
    private typealias Support = TimetableTestSupport

    private func page(_ context: NSManagedObjectContext, day: Date = Support.monday) -> SchedulesPageModel {
        SchedulesPageTestSupport.page(context, day: day)
    }

    private func setUpPage(_ context: NSManagedObjectContext) throws -> (SchedulesPageModel, [TimetableLaneSnapshot]) {
        try SchedulesPageTestSupport.setUpPage(context)
    }

    private func titles(_ lane: TimetableLaneSnapshot, in day: ScheduleDay) -> [String] {
        SchedulesPageTestSupport.titles(lane, in: day)
    }

    // MARK: - First run

    @Test("First run: no lanes until Set Up, then the three starter lanes and a person added after")
    func firstRun() throws {
        let context = try Support.context()
        let model = page(context)
        #expect(!model.hasLanes)

        #expect(model.setUp())
        #expect(model.lanes.map(\.name).prefix(2) == ["Our class", "Adolescent room"])
        #expect(model.lanes.map(\.kind) == [.room, .room, .person])
        #expect(model.lanes.last?.isGuide == true)
        #expect(model.editableLanes.count == 2)

        #expect(model.addPerson(named: "  Morah Devora "))
        #expect(model.lanes.last?.name == "Morah Devora")
        #expect(model.lanes.last?.kind == .person)
        #expect(model.personLanes.count == 2)
        #expect(!model.addPerson(named: "   "))
        #expect(model.lanes.count == 4)
        #expect(!context.hasChanges)
    }

    @Test("Lanes are renamed, recolored and reordered as the Lanes sheet leaves them")
    func laneEdits() throws {
        let context = try Support.context()
        let (model, _) = try setUpPage(context)
        var edits = model.laneEdits
        edits[1].name = "Upper room"
        edits[3].colorRaw = ScheduleLaneColor.teal.rawValue
        edits.move(fromOffsets: [3], toOffset: 0)
        edits[1].name = ""

        #expect(model.applyLaneEdits(edits))
        #expect(model.lanes.map(\.name) == ["Morah Devora", "Our class", "Upper room", model.lanes[3].name])
        #expect(model.lanes.first?.colorRaw == "teal")
        #expect(ScheduleLaneColor.of(try #require(model.lanes.first)) == .teal)
        #expect(model.lanes[3].isGuide)
    }

    // MARK: - Blocks

    @Test("A block on several days shows on each, and a turn shows in the teacher's lane too")
    func addBlockAndTurn() throws {
        let context = try Support.context()
        let (model, lanes) = try setUpPage(context)
        let room = lanes[1]
        let guide = lanes[2]
        let math = TimetableBlockValues(
            startMinute: Support.minutes(10, 30), lengthMinutes: 75, title: "Math", teacherLaneID: guide.id
        )
        #expect(model.addBlock(math, laneID: room.id, on: [.monday, .wednesday]))

        #expect(titles(room, in: model.resolved) == ["Math"])
        let turn = try #require(model.resolved.lane(guide.id)?.items.first)
        guard case .turn(let block) = turn.kind else {
            Issue.record("The guide's lane should show the room's block as a turn")
            return
        }
        #expect(block.laneID == room.id)

        model.day = Support.tuesday
        #expect(titles(room, in: model.resolved).isEmpty)
        model.day = Support.wednesday
        #expect(titles(room, in: model.resolved) == ["Math"])
        // From the start of the week shown: the week before doesn't have it.
        model.day = Support.lastMonday
        #expect(titles(room, in: model.resolved).isEmpty)
    }

    @Test("Only This Day changes one date; This Day and After changes that day and later, not earlier weeks")
    func editScopes() throws {
        let context = try Support.context()
        let (model, lanes) = try setUpPage(context)
        let room = lanes[0]
        model.day = Support.lastMonday
        #expect(model.addBlock(
            TimetableBlockValues(startMinute: Support.minutes(9), lengthMinutes: 60, title: "Work cycle"),
            laneID: room.id, on: [.monday]
        ))
        model.day = Support.monday
        let block = try #require(model.resolved.lane(room.id)?.items.first?.block)
        #expect(model.isRepeating(blockID: block.id))

        var changed = block.values
        changed.title = "Field day"
        #expect(model.edit(blockID: block.id, to: changed, scope: .onlyThisDay, on: Support.monday))
        #expect(titles(room, in: model.resolved) == ["Field day"])
        #expect(model.resolved.changeCount == 1)
        #expect(model.resolved.lane(room.id)?.items.first?.block?.isChanged == true)
        model.day = Support.nextMonday
        #expect(titles(room, in: model.resolved) == ["Work cycle"])

        #expect(model.undoChange(blockID: block.id, on: Support.monday))
        model.day = Support.monday
        #expect(titles(room, in: model.resolved) == ["Work cycle"])
        #expect(!model.resolved.isChanged)

        var later = block.values
        later.startMinute = Support.minutes(8, 45)
        #expect(model.edit(blockID: block.id, to: later, scope: .thisDayAndAfter, on: Support.monday))
        #expect(model.resolved.lane(room.id)?.items.first?.startMinute == Support.minutes(8, 45))
        model.day = Support.nextMonday
        #expect(model.resolved.lane(room.id)?.items.first?.startMinute == Support.minutes(8, 45))
        model.day = Support.lastMonday
        #expect(model.resolved.lane(room.id)?.items.first?.startMinute == Support.minutes(9))
    }

    @Test("Cancel This Day and Delete: one date, or from that day on")
    func cancelAndDelete() throws {
        let context = try Support.context()
        let (model, lanes) = try setUpPage(context)
        let room = lanes[0]
        model.day = Support.lastMonday
        #expect(model.addBlock(
            TimetableBlockValues(startMinute: Support.minutes(11), lengthMinutes: 30, title: "Recess"),
            laneID: room.id, on: [.monday]
        ))
        model.day = Support.monday
        let block = try #require(model.resolved.lane(room.id)?.items.first?.block)

        #expect(model.cancel(blockID: block.id, on: Support.monday))
        #expect(titles(room, in: model.resolved).isEmpty)
        #expect(model.resolved.changeCount == 1)
        #expect(model.undoAllChanges(on: Support.monday))
        #expect(titles(room, in: model.resolved) == ["Recess"])

        #expect(model.delete(blockID: block.id, scope: .thisDayAndAfter, on: Support.monday))
        #expect(titles(room, in: model.resolved).isEmpty)
        model.day = Support.nextMonday
        #expect(titles(room, in: model.resolved).isEmpty)
        model.day = Support.lastMonday
        #expect(titles(room, in: model.resolved) == ["Recess"])
    }

    @Test("Add to This Day makes a one-off, which doesn't repeat and counts as a change")
    func oneOff() throws {
        let context = try Support.context()
        let (model, lanes) = try setUpPage(context)
        let room = lanes[0]
        #expect(model.addOneOff(
            TimetableBlockValues(startMinute: Support.minutes(14), lengthMinutes: 15, title: "Early dismissal"),
            laneID: room.id, on: Support.monday
        ))
        let block = try #require(model.resolved.lane(room.id)?.items.first?.block)
        #expect(block.isOneOff)
        #expect(!model.isRepeating(blockID: block.id))
        #expect(model.resolved.changeCount == 1)
        #expect(ScheduleText.changeChip(count: model.resolved.changeCount, isToday: model.isToday) == "1 change today")
        model.day = Support.nextMonday
        #expect(titles(room, in: model.resolved).isEmpty)

        #expect(model.delete(blockID: block.id, scope: .everyWeek, on: Support.monday))
        model.day = Support.monday
        #expect(titles(room, in: model.resolved).isEmpty)
    }

    @Test("Out Today takes a person's blocks off the day and marks her turns; Back In restores them")
    func outToday() throws {
        let context = try Support.context()
        let (model, lanes) = try setUpPage(context)
        let room = lanes[1]
        let devora = lanes[3]
        #expect(model.addBlock(
            TimetableBlockValues(
                startMinute: Support.minutes(9), lengthMinutes: 60, title: "Humanities", teacherLaneID: devora.id
            ),
            laneID: room.id, on: [.monday]
        ))
        #expect(model.addBlock(
            TimetableBlockValues(startMinute: Support.minutes(13), lengthMinutes: 30, title: "Chumash"),
            laneID: devora.id, on: [.monday]
        ))

        #expect(model.setOut(laneID: devora.id, true, on: Support.monday))
        let lane = try #require(model.resolved.lane(devora.id))
        #expect(lane.isOut)
        #expect(lane.items.isEmpty)
        #expect(model.resolved.lane(room.id)?.items.first?.block?.teacherIsOut == true)

        #expect(model.setOut(laneID: devora.id, false, on: Support.monday))
        #expect(model.resolved.lane(devora.id)?.isOut == false)
        // Her own block, and her turn in the adolescent room again.
        #expect(titles(devora, in: model.resolved) == ["Humanities", "Chumash"])
    }

    @Test("Copy Day To… copies a weekday's blocks to the days picked")
    func copyDay() throws {
        let context = try Support.context()
        let (model, lanes) = try setUpPage(context)
        let room = lanes[0]
        #expect(model.addBlock(
            TimetableBlockValues(startMinute: Support.minutes(8, 30), lengthMinutes: 15, title: "Morning meeting"),
            laneID: room.id, on: [.monday]
        ))
        #expect(model.copyDay(.monday, laneID: room.id, to: [.tuesday, .wednesday]))
        model.mode = .week
        let byDay = model.week.map { titles(room, in: $0.resolved) }
        #expect(byDay == [["Morning meeting"], ["Morning meeting"], ["Morning meeting"], [], []])
    }
}
