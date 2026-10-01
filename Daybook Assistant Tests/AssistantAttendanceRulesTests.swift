import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The rules the assistant's grid runs on each morning: what a tap means in each
// phase, the names on a three-column phone grid, and closing arrival with its Undo.
@Suite("Assistant attendance rules")
@MainActor
struct AssistantAttendanceRulesTests {

    typealias Model = AssistantAttendanceViewModel

    // MARK: - Taps

    @Test("Arrival: a tap marks present and a second tap clears it")
    func arrivalTaps() {
        #expect(Model.statusAfterTap(from: .unmarked, in: .arrival) == .present)
        #expect(Model.statusAfterTap(from: .present, in: .arrival) == .unmarked)
        #expect(Model.statusAfterTap(from: .absent, in: .arrival) == .present)
        #expect(Model.statusAfterTap(from: .tardy, in: .arrival) == .present)
    }

    @Test("Late: a tap turns absent or unmarked into tardy, and back to absent")
    func lateTaps() {
        #expect(Model.statusAfterTap(from: .absent, in: .late) == .tardy)
        #expect(Model.statusAfterTap(from: .unmarked, in: .late) == .tardy)
        #expect(Model.statusAfterTap(from: .tardy, in: .late) == .absent)
    }

    @Test("Late: a present or left-early child is left alone by a tap")
    func lateLeavesPresentAlone() {
        #expect(Model.statusAfterTap(from: .present, in: .late) == nil)
        #expect(Model.statusAfterTap(from: .leftEarly, in: .late) == nil)
    }

    // MARK: - Grid names

    @Test("Grid names: first name alone, last initial for shared first names, full name when that clashes too")
    func gridNames() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let ettyG = AssistantTestSupport.student("Etty", "Goldman", in: context)
        let ettyR = AssistantTestSupport.student("Etty", "Rosen", in: context)
        let sarahR1 = AssistantTestSupport.student("Sarah", "Reed", in: context)
        let sarahR2 = AssistantTestSupport.student("Sarah", "Rubin", in: context)

        let names = AttendanceGridNames.names(for: [ari, ettyG, ettyR, sarahR1, sarahR2])

        #expect(names[ari.objectID] == "Ari")
        #expect(names[ettyG.objectID] == "Etty G")
        #expect(names[ettyR.objectID] == "Etty R")
        #expect(names[sarahR1.objectID] == "Sarah Reed")
        #expect(names[sarahR2.objectID] == "Sarah Rubin")
    }

    // MARK: - Remembered phase

    @Test("The Late phase is remembered for its own day only")
    func latePhaseMemory() throws {
        let defaults = AssistantTestSupport.makeDefaults()
        let monday = try AssistantTestSupport.day("2026-09-28")
        let tuesday = try AssistantTestSupport.day("2026-09-29")

        #expect(!AttendanceLatePhase.isLate(on: monday, defaults: defaults))
        AttendanceLatePhase.setLate(true, on: monday, defaults: defaults)
        #expect(AttendanceLatePhase.isLate(on: monday, defaults: defaults))
        #expect(!AttendanceLatePhase.isLate(on: tuesday, defaults: defaults))

        // Returning another day to Arrival doesn't forget Monday.
        AttendanceLatePhase.setLate(false, on: tuesday, defaults: defaults)
        #expect(AttendanceLatePhase.isLate(on: monday, defaults: defaults))

        AttendanceLatePhase.setLate(false, on: monday, defaults: defaults)
        #expect(!AttendanceLatePhase.isLate(on: monday, defaults: defaults))
    }

    @Test("Switching another day to Late keeps this day's Late")
    func latePhaseMemoryKeepsEachDay() throws {
        let defaults = AssistantTestSupport.makeDefaults()
        let monday = try AssistantTestSupport.day("2026-09-28")
        let tuesday = try AssistantTestSupport.day("2026-09-29")

        AttendanceLatePhase.setLate(true, on: tuesday, defaults: defaults)
        AttendanceLatePhase.setLate(true, on: monday, defaults: defaults)
        #expect(AttendanceLatePhase.isLate(on: tuesday, defaults: defaults))
        #expect(AttendanceLatePhase.isLate(on: monday, defaults: defaults))

        AttendanceLatePhase.setLate(false, on: monday, defaults: defaults)
        #expect(AttendanceLatePhase.isLate(on: tuesday, defaults: defaults))
        #expect(!AttendanceLatePhase.isLate(on: monday, defaults: defaults))
    }

    @Test("Only the most recent days are kept")
    func latePhaseMemoryIsBounded() throws {
        let defaults = AssistantTestSupport.makeDefaults()
        let first = try AssistantTestSupport.day("2026-08-01")
        let limit = AttendanceLatePhase.dayLimit
        let days = (0...limit).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: first) }
        for day in days { AttendanceLatePhase.setLate(true, on: day, defaults: defaults) }

        #expect(!AttendanceLatePhase.isLate(on: first, defaults: defaults))
        #expect(days.dropFirst().allSatisfy { AttendanceLatePhase.isLate(on: $0, defaults: defaults) })
    }

    @Test("A day remembered before each day kept its own is still Late")
    func latePhaseMemoryReadsSingleDayKey() throws {
        let defaults = AssistantTestSupport.makeDefaults()
        let monday = try AssistantTestSupport.day("2026-09-28")
        let tuesday = try AssistantTestSupport.day("2026-09-29")
        defaults.set(tuesday, forKey: "Assistant.latePhaseDay")

        #expect(AttendanceLatePhase.isLate(on: tuesday, defaults: defaults))
        AttendanceLatePhase.setLate(true, on: monday, defaults: defaults)
        #expect(AttendanceLatePhase.isLate(on: tuesday, defaults: defaults))
        #expect(AttendanceLatePhase.isLate(on: monday, defaults: defaults))
    }

    // MARK: - Closing arrival

    @Test("Closing arrival marks only the unmarked absent, and Undo clears exactly those")
    func closeArrivalAndUndo() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        for (first, last) in [("Ari", "Cedar"), ("Maya", "Stone"), ("Noah", "Linden"), ("Leah", "Hart")] {
            AssistantTestSupport.student(first, last, in: context)
        }
        let model = AssistantTestSupport.viewModel(stack)
        let ari = try #require(model.rows.first { $0.student.firstName == "Ari" })
        model.tap(ari)

        let marked = model.beginLate()

        #expect(marked == 3)
        #expect(model.phase == .late)
        let statuses = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.student.firstName, $0.status) })
        #expect(statuses == ["Ari": .present, "Leah": .absent, "Maya": .absent, "Noah": .absent])

        // One of them arrives late before the Undo.
        let noah = try #require(model.rows.first { $0.student.firstName == "Noah" })
        model.tap(noah)

        model.returnToArrival(undo: true)

        #expect(model.phase == .arrival)
        let after = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.student.firstName, $0.status) })
        #expect(after == ["Ari": .present, "Leah": .unmarked, "Maya": .unmarked, "Noah": .tardy])
    }

    @Test("Closing arrival is remembered, so a relaunch mid-morning stays on Late")
    func closeArrivalIsRemembered() throws {
        let stack = try AssistantTestSupport.makeStack()
        AssistantTestSupport.student("Ari", "Cedar", in: stack.viewContext)
        let defaults = AssistantTestSupport.makeDefaults()

        let first = AssistantTestSupport.viewModel(stack, defaults: defaults)
        first.beginLate()

        let relaunched = AssistantTestSupport.viewModel(stack, defaults: defaults)
        #expect(relaunched.phase == .late)
    }

    @Test("Late survives a trip to another day, so a child tapped in after is tardy")
    func lateSurvivesAnotherDay() throws {
        let stack = try AssistantTestSupport.makeStack()
        AssistantTestSupport.student("Ari", "Cedar", in: stack.viewContext)
        let today = Calendar.current.startOfDay(for: Date())
        let model = AssistantTestSupport.viewModel(stack, on: today)
        model.beginLate()

        // A look back at an earlier day, closing and reopening arrival there.
        model.load(try AssistantTestSupport.day("2026-09-21"))
        model.beginLate()
        model.returnToArrival(undo: true)

        model.load(today)
        #expect(model.phase == .late)
        let ari = try #require(model.rows.first)
        model.tap(ari)
        #expect(model.rows.first?.status == .tardy)
    }

    // MARK: - Days off

    @Test("A weekend and a day off on the guide's calendar take no attendance")
    func daysOff() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        let holiday = CDNonSchoolDay(context: context)
        holiday.date = try AssistantTestSupport.day("2026-10-07")
        holiday.reason = "Staff day"
        let bare = CDNonSchoolDay(context: context)
        bare.date = try AssistantTestSupport.day("2026-10-08")

        let model = AssistantTestSupport.viewModel(stack, on: try AssistantTestSupport.day("2026-10-03"))
        #expect(model.dayOff == .weekend)

        model.load(try AssistantTestSupport.day("2026-10-07"))
        #expect(model.dayOff == .holiday("Staff day"))

        model.load(try AssistantTestSupport.day("2026-10-08"))
        #expect(model.dayOff == .holiday(nil))

        model.load(try AssistantTestSupport.day("2026-10-06"))
        #expect(model.dayOff == nil)
    }

    @Test("Here counts late arrivals, not a child who left early; the rest go on the small line")
    func hereCount() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let names = [("Ari", "Cedar"), ("Maya", "Stone"), ("Noah", "Linden"), ("Leah", "Hart"), ("Eli", "Moss")]
        for (first, last) in names {
            AssistantTestSupport.student(first, last, in: context)
        }
        let model = AssistantTestSupport.viewModel(stack)
        let row = { (name: String) in try #require(model.rows.first { $0.student.firstName == name }) }
        model.setStatus(.present, for: try row("Ari"))
        model.setStatus(.tardy, for: try row("Maya"))
        model.setStatus(.leftEarly, for: try row("Noah"))
        model.markAbsent(reason: .none, for: try row("Leah"))

        #expect(Model.hereLine(model.rows) == "2 here")
        #expect(Model.detailLine(model.rows) == "1 late · 1 left early · 1 absent · 1 not marked")
    }
}
