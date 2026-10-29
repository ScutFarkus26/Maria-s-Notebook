import Foundation
import Testing
@testable import CosmicDaybook

/// Two of the resolver's rules, from the 2026-10-29 bug hunt: only the
/// adolescent room's blocks are the guide's turns for his adolescents'
/// lessons, and a block cancelled for the day is kept aside, so it can be
/// brought back on its own.
@Suite("Schedules: turns in the adolescent room, and cancels kept aside")
@MainActor
struct ScheduleDayTurnsAndCancelsTests {

    private typealias Support = TimetableTestSupport
    private let ourClass = Support.ourClass
    private let room = Support.adolescentRoom
    private let guide = Support.guide

    @Test("A block the guide teaches in our class is not his adolescent-room turn")
    func ourClassIsNotATurn() throws {
        let generalStudies = Support.block(
            ourClass, .monday, Support.minutes(9), 120, "General studies", teacher: guide
        )
        let algebra = ScheduleLessonSnapshot(id: UUID(), title: "Algebra", half: .morning, studentIDs: [Support.ari])
        let maps = ScheduleLessonSnapshot(
            id: UUID(), title: "Maps", half: .morning, minute: Support.minutes(9, 30), studentIDs: [Support.lucy]
        )
        let day = Support.resolve(Support.monday, blocks: [generalStudies], lessons: [algebra, maps])
        #expect(day.lane(ourClass.id)?.items.first?.block?.lessons.isEmpty == true)
        // It still shows in his lane, as a block he teaches there.
        #expect(Set(Support.titles(guide, in: day)) == ["turn:General studies", "Maps", "morning:Algebra"])
        #expect(day.warnings == [.adolescentLessonWithoutTurn(
            lessonID: algebra.id, lessonTitle: "Algebra", half: .morning
        )], "no lesson is during a turn in the adolescent room")

        // With a turn in the adolescent room that morning, the lesson goes there.
        let turn = Support.block(room, .monday, Support.minutes(11), 45, "Danny's turn", teacher: guide)
        let both = Support.resolve(Support.monday, blocks: [generalStudies, turn], lessons: [algebra])
        #expect(both.lane(room.id)?.items.first?.block?.lessons.map(\.id) == [algebra.id])
        #expect(both.lane(ourClass.id)?.items.first?.block?.lessons.isEmpty == true)
        #expect(both.warnings.isEmpty)

        // When no room's name says which is the adolescent room, any room he teaches counts, as before.
        let renamed = TimetableLaneSnapshot(id: room.id, name: "Room 12", kind: .room, sortOrder: 1)
        let unnamed = ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: Support.monday, lanes: [ourClass, renamed, guide], blocks: [generalStudies], lessons: [algebra],
            studentLevels: Support.levels, calendar: Support.calendar
        ))
        #expect(unnamed.lane(ourClass.id)?.items.first?.block?.lessons.map(\.id) == [algebra.id])
        #expect(ScheduleDayResolver.isAdolescentRoom(room))
        #expect(ScheduleDayResolver.isAdolescentRoom(TimetableLaneSnapshot(name: "The Adolescents", kind: .room)))
        #expect(!ScheduleDayResolver.isAdolescentRoom(ourClass))
        #expect(!ScheduleDayResolver.isAdolescentRoom(TimetableLaneSnapshot(name: "Adolescent helper", kind: .person)))
    }

    @Test("A block cancelled for the day is off it, and kept aside with its own values to be brought back")
    func cancelledBlocksKeptAside() {
        let math = Support.block(ourClass, .monday, Support.minutes(9), 60, "Math")
        let reading = Support.block(ourClass, .monday, Support.minutes(11), 30, "Reading")
        let cancelled = TimetableChangeSnapshot(day: Support.monday, kind: .cancelled, blockID: math.id)
        let moved = TimetableChangeSnapshot(
            day: Support.monday, kind: .changed, blockID: reading.id,
            values: TimetableBlockValues(startMinute: Support.minutes(12), lengthMinutes: 30, title: "Reading")
        )
        let monday = Support.resolve(Support.monday, blocks: [math, reading], changes: [cancelled, moved])
        #expect(Support.titles(ourClass, in: monday) == ["Reading"])
        #expect(monday.cancelledBlocks.map(\.id) == [math.id])
        #expect(monday.cancelledBlocks.first?.values == math.values)
        #expect(ScheduleText.bringBack(math.values) == "Bring Back Math at 9:00")
        #expect(ScheduleText.bringBack(TimetableBlockValues(startMinute: Support.minutes(13, 30)))
            == "Bring Back the 1:30 Block")
        #expect(Support.resolve(Support.nextMonday, blocks: [math], changes: [cancelled]).cancelledBlocks.isEmpty)
    }
}
