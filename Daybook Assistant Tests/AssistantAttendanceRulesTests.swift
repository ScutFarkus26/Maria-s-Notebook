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

        let names = Model.gridNames(for: [ari, ettyG, ettyR, sarahR1, sarahR2])

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

        #expect(!Model.LatePhaseMemory.isLate(on: monday, defaults: defaults))
        Model.LatePhaseMemory.setLate(true, on: monday, defaults: defaults)
        #expect(Model.LatePhaseMemory.isLate(on: monday, defaults: defaults))
        #expect(!Model.LatePhaseMemory.isLate(on: tuesday, defaults: defaults))

        // Returning another day to Arrival doesn't forget Monday.
        Model.LatePhaseMemory.setLate(false, on: tuesday, defaults: defaults)
        #expect(Model.LatePhaseMemory.isLate(on: monday, defaults: defaults))

        Model.LatePhaseMemory.setLate(false, on: monday, defaults: defaults)
        #expect(!Model.LatePhaseMemory.isLate(on: monday, defaults: defaults))
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
}
