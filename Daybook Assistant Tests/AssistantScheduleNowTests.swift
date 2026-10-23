import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The Schedule tab's Now card, its words, and the sample class's schedule
// (Plan - Schedules, Phase 2B).
@Suite("Assistant Schedule tab: Now and words")
@MainActor
struct AssistantScheduleNowTests: AssistantScheduleFixture {

    let stack: CoreDataStack
    let monday: Date
    let morning: Date

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        monday = try AssistantTestSupport.day("2026-10-26")
        morning = try #require(AppCalendar.shared.date(byAdding: .minute, value: 9 * 60 + 15, to: monday))
    }

    // MARK: - The Now card

    @Test("The Now card says who is where")
    func nowCard() throws {
        let lanes = makeLanes()
        block(lanes.ourClass, 8 * 60 + 30, 7 * 60, "School day")
        block(lanes.adolescent, 9 * 60, 90, "Humanities", teacher: lanes.guide)
        block(lanes.adolescent, 10 * 60 + 30, 75, "Math", teacher: lanes.coTeacher)
        block(lanes.coTeacher, 9 * 60, 45, "Chumash group")
        #expect(context.safeSave())
        let tab = model()

        let at915 = try #require(tab.nowCard(at: morning))
        guard case .lines(let lines) = at915 else {
            Issue.record("Expected who is where at 9:15, got \(at915)")
            return
        }
        #expect(lines.map(\.text) == [
            "Danny is in the adolescent room until 10:30.",
            "Morah Devora: Chumash group until 9:45.",
            "Our class: School day until 3:30.",
            "Adolescent room: Humanities until 10:30."
        ])

        let at1100 = try #require(AppCalendar.shared.date(byAdding: .minute, value: 11 * 60, to: monday))
        guard case .lines(let later) = try #require(tab.nowCard(at: at1100)) else {
            Issue.record("Expected who is where at 11:00")
            return
        }
        #expect(later.first?.text == "Danny is in our class.")
        #expect(later.dropFirst().first?.text == "Morah Devora is in the adolescent room until 11:45.")

        let early = try #require(AppCalendar.shared.date(byAdding: .minute, value: 7 * 60, to: monday))
        #expect(tab.nowCard(at: early) == .beforeSchool)
        let evening = try #require(AppCalendar.shared.date(byAdding: .minute, value: 18 * 60, to: monday))
        #expect(tab.nowCard(at: evening) == .afterSchool)

        // Another day has no Now card.
        tab.step(forward: true)
        #expect(tab.nowCard(at: morning) == nil)
    }

    @Test("Out Today shows on the Now card and the out line, and the turn reads Out")
    func outToday() throws {
        let lanes = makeLanes()
        block(lanes.ourClass, 8 * 60 + 30, 7 * 60, "School day")
        block(lanes.adolescent, 9 * 60, 90, "Math", teacher: lanes.coTeacher)
        let out = CDTimetableChange(context: context)
        out.day = monday
        out.kind = .out
        out.laneID = lanes.coTeacher.id?.uuidString
        #expect(context.safeSave())
        let tab = model()

        #expect(tab.outLines == ["Morah Devora is out."])
        #expect(tab.changedLine == "1 change today")
        let math = try #require(tab.rows.first { $0.title == "Math" })
        #expect(math.isOut)
        #expect(math.teacher == "Morah Devora is out")
        guard case .lines(let lines) = try #require(tab.nowCard(at: morning)) else {
            Issue.record("Expected who is where")
            return
        }
        #expect(lines.contains { $0.text == "Morah Devora is out today." })
    }

    @Test("Without a name from the guide or Apple, the guide reads Your guide")
    func guideFallbackName() throws {
        let lanes = makeLanes()
        block(lanes.ourClass, 8 * 60 + 30, 7 * 60, "School day")
        booking([student("Maya", "Stone", .upper)])
        #expect(context.safeSave())
        let tab = model(guideName: nil)
        #expect(tab.rows.contains { $0.title == "With Your guide" })
        #expect(tab.laneOptions.map(\.name).contains("Your guide"))
        guard case .lines(let lines) = try #require(tab.nowCard(at: morning)) else {
            Issue.record("Expected who is where")
            return
        }
        #expect(lines.first?.text == "Your guide is in our class.")
    }

    // MARK: - Words

    @Test("A room's name reads naturally after in")
    func roomPhrases() {
        #expect(AssistantScheduleRows.roomPhrase("Our class") == "our class")
        #expect(AssistantScheduleRows.roomPhrase("Adolescent room") == "the adolescent room")
        #expect(AssistantScheduleRows.roomPhrase("The gym") == "the gym")
        #expect(AssistantScheduleRows.roomPhrase("Room 12") == "the Room 12")
        #expect(AssistantScheduleRows.possessive("Chris") == "Chris'")
        #expect(AssistantScheduleRows.possessive("Danny") == "Danny's")
    }

    // MARK: - The sample class

    @Test("The sample class has a schedule: lanes, a change today, and the guide's lessons as children")
    func sampleClassSchedule() throws {
        let sample = try AssistantSampleClass.makeStack()
        let tab = AssistantScheduleModel(context: sample.viewContext, guideName: { AssistantSampleClass.guideName })
        tab.load()
        #expect(tab.laneOptions.map(\.name) == [
            "Our class", "Adolescent room", AssistantSampleClass.guideName, AssistantSampleClass.coTeacherName
        ])
        let bookings = sample.viewContext.safeFetch(CDFetchRequest(CDTimetableBooking.self))
        #expect(bookings.count == 2)
        guard tab.dayOff == nil else { return } // A weekend shows no school; the rest needs a school day.
        #expect(tab.changedLine == "1 change today")
        #expect(tab.rows.contains { $0.title == "With \(AssistantSampleClass.guideName)" })
        #expect(tab.rows.contains { $0.title == "Humanities" && $0.children.count == 2 })
    }
}
