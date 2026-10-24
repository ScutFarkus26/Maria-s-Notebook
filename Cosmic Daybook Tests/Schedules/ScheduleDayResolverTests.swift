import Foundation
import Testing
@testable import CosmicDaybook

/// The day's rules, worked out once (`ScheduleDayResolver`): which blocks
/// apply, the day's changes, turns, the guide's lessons and where the
/// adolescents' go, the warnings, and what each lane has now.
@Suite("Schedules: the day resolver")
@MainActor
struct ScheduleDayResolverTests {

    private typealias Support = TimetableTestSupport
    private let ourClass = Support.ourClass
    private let room = Support.adolescentRoom
    private let guide = Support.guide
    private let devora = Support.devora

    // MARK: - Rules 1 and 2

    @Test("A weekly block shows on its weekday only, and Friday is its own day")
    func weeklyBlocksAndFriday() {
        let blocks = [
            Support.block(ourClass, .monday, Support.minutes(8, 30), 180, "Morning work"),
            Support.block(ourClass, .friday, Support.minutes(8, 30), 120, "Short day"),
            Support.block(ourClass, .friday, Support.minutes(12), 15, "Dismissal")
        ]
        #expect(Support.titles(ourClass, in: Support.resolve(Support.monday, blocks: blocks)) == ["Morning work"])
        let friday = Support.resolve(Support.friday, blocks: blocks)
        #expect(Support.titles(ourClass, in: friday) == ["Short day", "Dismissal"])
        #expect(Support.titles(ourClass, in: Support.resolve(Support.tuesday, blocks: blocks)).isEmpty)
    }

    @Test("A block applies only between its first and last days (This Day and After across weeks)")
    func validDaysBoundABlock() {
        let blocks = [
            Support.block(ourClass, .monday, Support.minutes(9), 60, "Old", until: Support.day(2026, 10, 25)),
            Support.block(ourClass, .monday, Support.minutes(9), 45, "New", from: Support.monday)
        ]
        #expect(Support.titles(ourClass, in: Support.resolve(Support.lastMonday, blocks: blocks)) == ["Old"])
        #expect(Support.titles(ourClass, in: Support.resolve(Support.monday, blocks: blocks)) == ["New"])
        #expect(Support.titles(ourClass, in: Support.resolve(Support.nextMonday, blocks: blocks)) == ["New"])
    }

    @Test("No school: every lane is empty, whatever the day holds")
    func noSchool() {
        let blocks = [
            Support.block(ourClass, .monday, Support.minutes(9), 60, "Morning work"),
            Support.block(ourClass, oneOff: Support.monday, Support.minutes(13), 30, "Assembly")
        ]
        let lesson = ScheduleLessonSnapshot(id: UUID(), title: "Fractions", half: .morning, studentIDs: [Support.lucy])
        let day = Support.resolve(Support.monday, blocks: blocks, lessons: [lesson], isSchoolDay: false)
        #expect(!day.isSchoolDay)
        #expect(day.lanes.count == 4)
        #expect(day.lanes.allSatisfy { $0.items.isEmpty })
        #expect(day.warnings.isEmpty)
        #expect(!day.isChanged)
    }

    // MARK: - Rule 3

    @Test("A one-off shows on its day only, and marks the day changed")
    func oneOffMarksTheDay() {
        let blocks = [Support.block(ourClass, oneOff: Support.tuesday, Support.minutes(9), 30, "Assembly")]
        let tuesday = Support.resolve(Support.tuesday, blocks: blocks)
        #expect(Support.titles(ourClass, in: tuesday) == ["Assembly"])
        #expect(tuesday.changeCount == 1)
        #expect(tuesday.lane(ourClass.id)?.items.first?.block?.isDayChange == true)
        let wednesday = Support.resolve(Support.wednesday, blocks: blocks)
        #expect(Support.titles(ourClass, in: wednesday).isEmpty)
        #expect(!wednesday.isChanged)
    }

    @Test("Cancelled hides a block and changed replaces its values that day; the newest change wins")
    func cancelledAndChanged() {
        let math = Support.block(ourClass, .monday, Support.minutes(9), 60, "Math")
        let reading = Support.block(ourClass, .monday, Support.minutes(11), 30, "Reading")
        var moved = TimetableChangeSnapshot(
            day: Support.monday, kind: .changed, blockID: math.id,
            values: TimetableBlockValues(startMinute: Support.minutes(10), lengthMinutes: 60, title: "Math"),
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let cancelledLater = TimetableChangeSnapshot(
            day: Support.monday, kind: .cancelled, blockID: math.id, modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let readingLonger = TimetableChangeSnapshot(
            day: Support.monday, kind: .changed, blockID: reading.id,
            values: TimetableBlockValues(startMinute: Support.minutes(11), lengthMinutes: 60, title: "Reading aloud"),
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let monday = Support.resolve(
            Support.monday, blocks: [math, reading], changes: [moved, cancelledLater, readingLonger]
        )
        #expect(Support.titles(ourClass, in: monday) == ["Reading aloud"], "the newer cancel wins over the move")
        let changed = monday.lane(ourClass.id)?.items.first?.block
        #expect(changed?.values.lengthMinutes == 60)
        #expect(changed?.isChanged == true)
        #expect(monday.changeCount == 2)

        // The other way round, the move wins.
        moved.modifiedAt = Date(timeIntervalSince1970: 300)
        let movedDay = Support.resolve(Support.monday, blocks: [math], changes: [moved, cancelledLater])
        #expect(movedDay.lane(ourClass.id)?.items.first?.startMinute == Support.minutes(10))

        // The next week is as every week.
        let next = Support.resolve(
            Support.nextMonday, blocks: [math, reading], changes: [cancelledLater, readingLonger]
        )
        #expect(Support.titles(ourClass, in: next) == ["Math", "Reading"])
        #expect(!next.isChanged)
    }

    // MARK: - Rule 4

    @Test("A turn shows in the room and in its teacher's lane as one block, so a change shows in both")
    func turnsShowTwice() throws {
        let turn = Support.block(room, .monday, Support.minutes(10, 30), 75, "Math", teacher: devora)
        let plain = Support.resolve(Support.monday, blocks: [turn])
        #expect(Support.titles(room, in: plain) == ["Math"])
        #expect(Support.titles(devora, in: plain) == ["turn:Math"])
        let roomBlock = try #require(plain.lane(room.id)?.items.first?.block)
        let turnBlock = try #require(plain.lane(devora.id)?.items.first?.block)
        #expect(roomBlock.id == turnBlock.id)
        #expect(turnBlock.laneID == room.id)

        let later = TimetableChangeSnapshot(
            day: Support.monday, kind: .changed, blockID: turn.id,
            values: TimetableBlockValues(
                startMinute: Support.minutes(11), lengthMinutes: 60, title: "Math", teacherLaneID: devora.id
            )
        )
        let changed = Support.resolve(Support.monday, blocks: [turn], changes: [later])
        #expect(changed.lane(room.id)?.items.first?.startMinute == Support.minutes(11))
        #expect(changed.lane(devora.id)?.items.first?.startMinute == Support.minutes(11))
    }

    @Test("Out Today cancels that person's blocks and marks their turns Out")
    func outToday() throws {
        let group = Support.block(devora, .monday, Support.minutes(9), 45, "Chumash", children: [Support.lucy])
        let turn = Support.block(room, .monday, Support.minutes(10, 30), 75, "Navi", teacher: devora)
        let out = TimetableChangeSnapshot(day: Support.monday, kind: .out, laneID: devora.id)
        let lesson = ScheduleLessonSnapshot(id: UUID(), title: "Fractions", half: .morning, studentIDs: [Support.lucy])
        let day = Support.resolve(Support.monday, blocks: [group, turn], changes: [out], lessons: [lesson])

        let devoraLane = try #require(day.lane(devora.id))
        #expect(devoraLane.isOut)
        #expect(devoraLane.items.isEmpty, "her own block is off, and her turn isn't shown in her lane")
        let roomBlock = try #require(day.lane(room.id)?.items.first?.block)
        #expect(roomBlock.teacherIsOut)
        #expect(day.changeCount == 1)
        #expect(day.warnings.isEmpty, "Lucy isn't with her today")

        let nextWeek = Support.resolve(Support.nextMonday, blocks: [group, turn], changes: [out])
        #expect(nextWeek.lane(devora.id)?.isOut == false)
        #expect(Support.titles(devora, in: nextWeek) == ["Chumash", "turn:Navi"])
    }

    // MARK: - Rule 5

    @Test("The guide's lessons: each half's list in his order, and a set time at its time")
    func guideLessons() {
        let lessons = [
            ScheduleLessonSnapshot(id: UUID(), title: "Second", half: .morning, order: 1, studentIDs: [Support.lucy]),
            ScheduleLessonSnapshot(id: UUID(), title: "First", half: .morning, order: 0, studentIDs: [Support.lucy]),
            ScheduleLessonSnapshot(id: UUID(), title: "Afternoon", half: .afternoon, studentIDs: [Support.lucy]),
            ScheduleLessonSnapshot(
                id: UUID(), title: "At ten", half: .morning, minute: Support.minutes(10), studentIDs: [Support.lucy]
            )
        ]
        let day = Support.resolve(Support.monday, blocks: [], lessons: lessons)
        #expect(Support.titles(guide, in: day) == ["morning:First+Second", "At ten", "afternoon:Afternoon"])
        #expect(day.lane(guide.id)?.items.map(\.startMinute) == [540, 600, 840])
    }

    @Test("An adolescents-only lesson goes into the guide's turn that half; with none, it stays with a note")
    func adolescentPlacement() throws {
        let turn = Support.block(room, .monday, Support.minutes(10, 30), 75, "Danny's turn", teacher: guide)
        let onlyAdolescents = ScheduleLessonSnapshot(
            id: UUID(), title: "Algebra", half: .morning, studentIDs: [Support.ari, Support.bea]
        )
        let atEleven = ScheduleLessonSnapshot(
            id: UUID(), title: "Poetry", half: .morning, minute: Support.minutes(11), studentIDs: [Support.ari]
        )
        let afternoon = ScheduleLessonSnapshot(
            id: UUID(), title: "Geometry", half: .afternoon, studentIDs: [Support.bea]
        )
        let mixed = ScheduleLessonSnapshot(
            id: UUID(), title: "History", half: .morning, studentIDs: [Support.lucy, Support.ari]
        )
        let day = Support.resolve(
            Support.monday, blocks: [turn], lessons: [onlyAdolescents, atEleven, afternoon, mixed]
        )

        let roomBlock = try #require(day.lane(room.id)?.items.first?.block)
        #expect(roomBlock.lessons.map(\.snapshot.title) == ["Algebra", "Poetry"])
        #expect(Set(roomBlock.studentIDs) == [Support.ari, Support.bea])
        #expect(Support.titles(guide, in: day) == ["morning:History", "turn:Danny's turn", "afternoon:Geometry"])
        let guideTurn = try #require(day.lane(guide.id)?.items.first { $0.block != nil }?.block)
        #expect(guideTurn.lessons.map(\.snapshot.title) == ["Algebra", "Poetry"], "the same block in both lanes")

        guard case .halfList(_, let afternoonList)? = day.lane(guide.id)?.items.last?.kind else {
            Issue.record("the afternoon list is last")
            return
        }
        #expect(afternoonList.first?.note == "No turn in the adolescent room this afternoon")
        #expect(afternoonList.first?.isAdolescentsOnly == true)
        guard case .halfList(_, let morningList)? = day.lane(guide.id)?.items.first?.kind else {
            Issue.record("the morning list is first")
            return
        }
        #expect(morningList.first?.isAdolescentsOnly == false)
        #expect(morningList.first?.note == nil)
        #expect(day.warnings == [.adolescentLessonWithoutTurn(
            lessonID: afternoon.id, lessonTitle: "Geometry", half: .afternoon
        )])
    }

    // MARK: - Rule 6

    @Test("The three warnings, worded plainly")
    func warnings() {
        let group = Support.block(devora, .monday, Support.minutes(9), 45, "Chumash", children: [Support.lucy])
        let turn = Support.block(room, .monday, Support.minutes(10, 30), 75, "Danny's turn", teacher: guide)
        let fractions = ScheduleLessonSnapshot(
            id: UUID(), title: "Fractions", half: .morning, studentIDs: [Support.lucy]
        )
        let duringTurn = ScheduleLessonSnapshot(
            id: UUID(), title: "Maps", half: .morning, minute: Support.minutes(10, 45),
            studentIDs: [Support.lucy, Support.ari]
        )
        let noTurn = ScheduleLessonSnapshot(id: UUID(), title: "Algebra", half: .afternoon, studentIDs: [Support.ari])
        let afternoonLucy = ScheduleLessonSnapshot(
            id: UUID(), title: "Art", half: .afternoon, studentIDs: [Support.lucy]
        )
        let day = Support.resolve(
            Support.monday, blocks: [group, turn], lessons: [fractions, duringTurn, noTurn, afternoonLucy]
        )
        let names = [Support.lucy: "Lucy T"]
        let texts = day.warnings.map { $0.text { names[$0] } }
        #expect(texts == [
            "Lucy T is with Morah Devora 9:00–9:45 this morning.",
            "Maps at 10:45 is during your turn in the adolescent room (10:30–11:45).",
            "Algebra is for adolescents only, but you have no turn in the adolescent room this afternoon."
        ])
        #expect(day.warnings.first?.lessonID == fractions.id)

        // Without titles (the Assistant), the words name no lesson.
        let untitled = day.warnings.map { warning -> String in
            switch warning {
            case let .lessonDuringTurn(id, _, minute, turnID, values):
                ScheduleDay.Warning.lessonDuringTurn(
                    lessonID: id, lessonTitle: nil, minute: minute, turnID: turnID, turnValues: values
                ).text { _ in nil }
            default: warning.text { _ in nil }
            }
        }
        #expect(untitled[0] == "A child is with Morah Devora 9:00–9:45 this morning.")
        #expect(untitled[1] == "A lesson at 10:45 is during your turn in the adolescent room (10:30–11:45).")
    }

    @Test("When the guide is out, his turns take no lessons and nothing warns about them")
    func guideOut() {
        let turn = Support.block(room, .monday, Support.minutes(10, 30), 75, "Danny's turn", teacher: guide)
        let algebra = ScheduleLessonSnapshot(id: UUID(), title: "Algebra", half: .morning, studentIDs: [Support.ari])
        let out = TimetableChangeSnapshot(day: Support.monday, kind: .out, laneID: guide.id)
        let day = Support.resolve(Support.monday, blocks: [turn], changes: [out], lessons: [algebra])
        #expect(day.lane(room.id)?.items.first?.block?.teacherIsOut == true)
        #expect(day.lane(room.id)?.items.first?.block?.lessons.isEmpty == true)
        #expect(Support.titles(guide, in: day) == ["morning:Algebra"])
        #expect(day.warnings.isEmpty)
    }

    // MARK: - Now

    @Test("Now: what each lane has under way, a turn naming its room and when it ends")
    func now() throws {
        let morningWork = Support.block(ourClass, .monday, Support.minutes(8, 30), 180, "Morning work")
        let turn = Support.block(room, .monday, Support.minutes(10, 30), 75, "Navi", teacher: devora)
        let day = Support.resolve(Support.monday, blocks: [morningWork, turn])
        let entries = day.now(at: Support.minutes(10, 45))
        #expect(entries.map(\.lane.name) == ["Our class", "Adolescent room", "Danny", "Morah Devora"])
        let devoraNow = try #require(entries.last)
        #expect(devoraNow.block?.values.title == "Navi")
        #expect(devoraNow.roomLaneID == room.id)
        #expect(devoraNow.until == Support.minutes(11, 45))
        #expect(entries[2].block == nil, "the guide has nothing under way")
        #expect(entries[0].roomLaneID == nil)
        #expect(day.now(at: Support.minutes(11, 45)).last?.block == nil, "a block's end isn't in it")
    }
}
