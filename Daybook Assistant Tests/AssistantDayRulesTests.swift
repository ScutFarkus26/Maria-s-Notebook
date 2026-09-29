import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Days ahead take absences only; past days take everything but carry no time;
// and the error line clears when the thing that failed works again.
@Suite("Assistant day rules and errors")
@MainActor
struct AssistantDayRulesTests {

    typealias Model = AssistantAttendanceViewModel

    private func classOfTwo() throws -> CoreDataStack {
        let stack = try AssistantTestSupport.makeStack()
        AssistantTestSupport.student("Ari", "Cedar", in: stack.viewContext)
        AssistantTestSupport.student("Maya", "Stone", in: stack.viewContext)
        return stack
    }

    private func row(_ first: String, in model: Model) throws -> Model.Row {
        try #require(model.rows.first { $0.student.firstName == first })
    }

    // MARK: - Ahead

    @Test("Ahead of the day: taps do nothing, and only Absent or clearing is allowed")
    func futureDayTakesAbsencesOnly() throws {
        let stack = try classOfTwo()
        let ahead = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let model = AssistantTestSupport.viewModel(stack, on: ahead)
        #expect(model.isFuture)
        #expect(model.menuStatuses == [.absent, .unmarked])

        let ari = try row("Ari", in: model)
        #expect(model.statusAfterTap(for: ari) == nil)
        model.tap(ari)
        #expect(try row("Ari", in: model).status == .unmarked)

        model.setStatus(.present, for: ari)
        #expect(try row("Ari", in: model).status == .unmarked)

        model.setStatus(.absent, for: ari)
        let marked = try row("Ari", in: model)
        #expect(marked.status == .absent)
        #expect(marked.markedAt == nil)

        #expect(model.beginLate() == 0)
        #expect(model.phase == .arrival)
        #expect(try row("Maya", in: model).status == .unmarked)
    }

    @Test("The rule itself: today and past allow everything; ahead allows Absent and clearing")
    func allowsRule() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        for status in AttendanceStatus.allCases {
            #expect(Model.allows(status, on: now, now: now))
            #expect(Model.allows(status, on: yesterday, now: now))
        }
        #expect(Model.allows(.absent, on: tomorrow, now: now))
        #expect(Model.allows(.unmarked, on: tomorrow, now: now))
        #expect(!Model.allows(.present, on: tomorrow, now: now))
        #expect(!Model.allows(.tardy, on: tomorrow, now: now))
        #expect(!Model.allows(.leftEarly, on: tomorrow, now: now))
    }

    // MARK: - Past

    @Test("A past day takes every mark and Late, but records no time")
    func pastDayTakesEverythingWithoutTimes() throws {
        let stack = try classOfTwo()
        let past = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let model = AssistantTestSupport.viewModel(stack, on: past)
        #expect(!model.isFuture)
        #expect(model.menuStatuses.count == AttendanceStatus.allCases.count)

        model.tap(try row("Ari", in: model))
        let ari = try row("Ari", in: model)
        #expect(ari.status == .present)
        #expect(ari.markedAt == nil)

        #expect(model.beginLate() == 1)
        #expect(try row("Maya", in: model).status == .absent)
    }

    // MARK: - Errors

    @Test("A failed save says so, survives a reload, and clears when a save works")
    func saveErrorClearsOnSuccess() throws {
        let stack = try classOfTwo()
        let context = stack.viewContext
        _ = context.safeSave()
        let model = AssistantTestSupport.viewModel(stack)
        #expect(model.errorMessage == nil)

        // An invalid record on a far-off day makes every save fail without
        // appearing on the day being loaded.
        let broken = CDAttendanceRecord(context: context)
        broken.date = try AssistantTestSupport.day("2020-01-06")
        broken.setValue(nil, forKey: "studentID")

        model.tap(try row("Ari", in: model))
        #expect(model.errorMessage == "Couldn't save that change. Try again.")

        model.load()
        #expect(model.errorMessage != nil)

        context.delete(broken)
        model.tap(try row("Maya", in: model))
        #expect(model.errorMessage == nil)
    }
}
