import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The Schedule tab (Plan - Schedules, Phase 2B): it reads the classroom
// share's lanes, blocks, changes and bookings, works the day out with the
// notebook's resolver, and shows the guide's lessons as children only.
@Suite("Assistant Schedule tab")
@MainActor
struct AssistantScheduleTests: AssistantScheduleFixture {

    let stack: CoreDataStack
    let monday: Date
    let morning: Date

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        monday = try AssistantTestSupport.day("2026-10-26")
        morning = try #require(AppCalendar.shared.date(byAdding: .minute, value: 9 * 60 + 15, to: monday))
    }

    // MARK: - Loading

    @Test("Before the guide sets anything up the tab says so; a reload shows what arrived")
    func loadAndReload() throws {
        let tab = model()
        #expect(tab.resolved != nil)
        #expect(!tab.hasLanes)
        #expect(tab.rows.isEmpty)

        // The guide's lanes and a block arrive (an import, stood in for by a save here).
        let lanes = makeLanes()
        let meeting = block(lanes.ourClass, 8 * 60 + 30, 15, "Morning meeting")
        block(lanes.ourClass, 8 * 60 + 45, 180, "Work period")
        #expect(context.safeSave())
        tab.load()
        #expect(tab.hasLanes)
        #expect(tab.rows.map(\.title) == ["Morning meeting", "Work period"])
        #expect(tab.rows.map(\.time) == ["8:30–8:45", "8:45–11:45"])
        #expect(tab.rows.allSatisfy { $0.laneName == "Our class" })
        #expect(tab.changedLine == nil)
        #expect(tab.laneOptions.map(\.name) == ["Our class", "Adolescent room", "Danny", "Morah Devora"])
        #expect(tab.headerLine.hasPrefix("Monday, October 26"))
        #expect(tab.headerLine.contains("Cheshvan"))

        // The guide cancels the meeting for today only.
        let change = CDTimetableChange(context: context)
        change.day = monday
        change.kind = .cancelled
        change.blockID = meeting.id?.uuidString
        #expect(context.safeSave())
        tab.load()
        #expect(tab.rows.map(\.title) == ["Work period"])
        #expect(tab.changedLine == "1 change today")

        // The next school day, a Tuesday, has no Monday blocks and no change.
        tab.step(forward: true)
        #expect(AppCalendar.shared.component(.weekday, from: tab.day) == 3)
        #expect(tab.rows.isEmpty)
        #expect(tab.changedLine == nil)
        #expect(!tab.isToday)
        tab.showToday()
        #expect(tab.isToday)
    }

    @Test("A weekend is no school, and stepping skips it")
    func weekendIsNoSchool() throws {
        let lanes = makeLanes()
        block(lanes.ourClass, 9 * 60, 60, "Work period", weekday: .friday)
        #expect(context.safeSave())
        let tab = model()
        tab.step(forward: false)
        // Back from Monday lands on Friday, not Sunday.
        #expect(AppCalendar.shared.component(.weekday, from: tab.day) == 6)
        #expect(tab.rows.map(\.title) == ["Work period"])
        tab.show(try AssistantTestSupport.day("2026-10-25"))
        #expect(tab.dayOff == .weekend)
        #expect(tab.rows.isEmpty)
        #expect(tab.nowCard(at: morning) == nil)
    }

    @Test("Two copies of one booking show once, the newest")
    func duplicateBookingsShowOnce() throws {
        let lanes = makeLanes()
        _ = lanes
        let maya = student("Maya", "Stone", .upper)
        let eli = student("Eli", "Brooks", .upper)
        let presentation = UUID()
        booking([maya], presentationID: presentation, sourceModifiedAt: monday)
        booking([maya, eli], presentationID: presentation, sourceModifiedAt: monday.addingTimeInterval(60))
        #expect(context.safeSave())
        let rows = model().rows.filter { $0.kind == .withGuide }
        #expect(rows.count == 1)
        #expect(rows.first?.children == ["Maya S", "Eli B"])
    }

    // MARK: - The guide's lessons

    @Test("An adolescents-only booking goes into the guide's turn; a mixed one is a With row")
    func adolescentPlacementFromBookings() throws {
        let lanes = makeLanes()
        block(lanes.adolescent, 9 * 60, 90, "Humanities", teacher: lanes.guide)
        let noah = student("Noah", "Linden", .adolescent)
        let tamar = student("Tamar", "Reed", .adolescent)
        let maya = student("Maya", "Stone", .upper)
        booking([noah, tamar], minute: 9 * 60 + 30, order: 0)
        booking([maya, noah], half: .morning, order: 1)
        booking([maya], half: .afternoon, order: 0)
        #expect(context.safeSave())
        let tab = model()

        // Every lane: the room's block names the turn and its children; the
        // mixed lessons are With rows by half.
        let humanities = try #require(tab.rows.first { $0.title == "Humanities" })
        #expect(humanities.laneName == "Adolescent room")
        #expect(humanities.teacher == "Danny's turn")
        #expect(humanities.children == ["Noah L", "Tamar R"])
        let with = tab.rows.filter { $0.kind == .withGuide }
        #expect(with.map(\.title) == ["With Danny", "With Danny"])
        #expect(with.map(\.time) == ["Morning", "Afternoon"])
        #expect(with.map(\.children) == [["Maya S", "Noah L"], ["Maya S"]])
        #expect(!tab.rows.contains { $0.kind == .turn })

        // The guide's lane alone: the turn shows there, with its children.
        tab.laneFilter = lanes.guide.id
        let turn = try #require(tab.rows.first { $0.kind == .turn })
        #expect(turn.title == "In the adolescent room · Humanities")
        #expect(turn.children == ["Noah L", "Tamar R"])
        #expect(turn.laneName == "Danny")
        #expect(tab.rows.allSatisfy { $0.laneID == lanes.guide.id })
    }

    @Test("No lesson's name can reach the tab, even with the lessons in the same store")
    func noLessonTitleAnywhere() throws {
        let secret = "Golden Bead Addition"
        let lanes = makeLanes()
        block(lanes.ourClass, 8 * 60 + 30, 7 * 60, "School day")
        block(lanes.adolescent, 9 * 60, 90, "Humanities", teacher: lanes.guide)
        let noah = student("Noah", "Linden", .adolescent)
        let maya = student("Maya", "Stone", .upper)
        let presentationID = UUID()
        booking([noah], minute: 9 * 60 + 30, presentationID: presentationID)
        booking([maya, noah], half: .afternoon, order: 0)

        // The planned presentation and its lesson, named, beside the booking:
        // the notebook's private types, which never reach the share, put
        // here to show nothing reads them.
        let lesson = NSEntityDescription.insertNewObject(forEntityName: "Lesson", into: context)
        lesson.setValue(UUID(), forKey: "id")
        lesson.setValue(secret, forKey: "name")
        let planned = NSEntityDescription.insertNewObject(forEntityName: "LessonAssignment", into: context)
        planned.setValue(presentationID, forKey: "id")
        planned.setValue(secret, forKey: "lessonTitleSnapshot")
        planned.setValue(monday, forKey: "scheduledForDay")
        #expect(context.safeSave())

        let tab = model()
        for lane in [nil] + tab.laneOptions.map(\.id) {
            tab.laneFilter = lane
            let shown = Self.strings(in: tab.rows) + Self.strings(in: tab.nowCard(at: morning) as Any)
            #expect(!shown.isEmpty)
            #expect(!shown.contains { $0.localizedCaseInsensitiveContains(secret) })
        }
        let everything = Self.strings(in: tab.resolved as Any) + Self.strings(in: tab.laneOptions)
            + [tab.headerLine, tab.changedLine ?? ""] + tab.outLines + Array(tab.childNames.values)
        #expect(!everything.contains { $0.localizedCaseInsensitiveContains(secret) })

        // Every lesson the tab worked out carries no title at all.
        let resolved = try #require(tab.resolved)
        let lessons = resolved.lanes.flatMap(\.items).flatMap { item -> [ScheduleDay.Lesson] in
            switch item.kind {
            case .block(let block), .turn(let block): block.lessons
            case .lesson(let lesson): [lesson]
            case .halfList(_, let list): list
            }
        }
        #expect(lessons.count >= 2)
        #expect(lessons.allSatisfy { $0.snapshot.title == nil })

        // And a booking has no text attribute that could carry one.
        let entity = try #require(NSEntityDescription.entity(forEntityName: "TimetableBooking", in: context))
        let textAttributes = entity.attributesByName.filter { $0.value.attributeType == .stringAttributeType }
        #expect(Set(textAttributes.keys) == ["presentationID", "halfRaw"])
    }

    /// Every string inside `value`, however deep.
    private static func strings(in value: Any, depth: Int = 0) -> [String] {
        guard depth < 24 else { return [] }
        if let string = value as? String { return [string] }
        if let substring = value as? Substring { return [String(substring)] }
        return Mirror(reflecting: value).children.flatMap { strings(in: $0.value, depth: depth + 1) }
    }
}
