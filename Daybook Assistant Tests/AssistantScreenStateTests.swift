import Foundation
import CoreData
import CloudKit
import Testing
@testable import Daybook_Assistant

// What the screen offers and says: Close Arrival and its Undo, a locked day,
// an empty note, the "sent" line, and when the stack is rebuilt for iCloud.
@Suite("Assistant screen state")
@MainActor
struct AssistantScreenStateTests {

    typealias Model = AssistantAttendanceViewModel

    private func classOfTwo() throws -> CoreDataStack {
        let stack = try AssistantTestSupport.makeStack()
        AssistantTestSupport.student("Ari", "Cedar", in: stack.viewContext)
        AssistantTestSupport.student("Maya", "Stone", in: stack.viewContext)
        _ = stack.viewContext.safeSave()
        return stack
    }

    private func row(_ first: String, in model: Model) throws -> Model.Row {
        try #require(model.rows.first { $0.student.firstName == first })
    }

    private func recordCount(_ stack: CoreDataStack) throws -> Int {
        try stack.viewContext.count(for: CDFetchRequest(CDAttendanceRecord.self))
    }

    @Test("Close Arrival is offered while someone is unmarked, then Late shows; never on a day ahead")
    func arrivalControl() throws {
        let stack = try classOfTwo()
        let model = AssistantTestSupport.viewModel(stack)
        #expect(model.showsArrivalControl)
        #expect(model.unmarkedNames == ["Ari", "Maya"])

        model.tap(try row("Ari", in: model))
        #expect(model.unmarkedNames == ["Maya"])
        model.tap(try row("Maya", in: model))
        #expect(!model.showsArrivalControl)

        model.beginLate()
        #expect(model.showsArrivalControl)

        let ahead = try #require(Calendar.current.date(byAdding: .day, value: 3, to: Date()))
        #expect(!AssistantTestSupport.viewModel(stack, on: ahead).showsArrivalControl)
    }

    @Test("A locked day takes no marks, no notes and no Close Arrival")
    func lockedDay() throws {
        let stack = try classOfTwo()
        let today = Calendar.current.startOfDay(for: Date())
        #expect(AttendanceDayLocks.setLocked(true, for: today, role: .leadGuide, in: stack.viewContext))
        let model = AssistantTestSupport.viewModel(stack, on: today)
        #expect(model.isLocked)
        #expect(!model.canMark)
        #expect(!model.showsArrivalControl)

        let ari = try row("Ari", in: model)
        model.tap(ari)
        model.setStatus(.present, for: ari)
        model.markAbsent(reason: .none, for: ari)
        model.setNote("Early pickup", for: ari)
        #expect(model.beginLate() == 0)
        #expect(model.phase == .arrival)
        #expect(try recordCount(stack) == 0)
    }

    @Test("Saving an empty note on an unmarked child leaves no record behind")
    func emptyNoteMakesNoRecord() throws {
        let stack = try classOfTwo()
        let model = AssistantTestSupport.viewModel(stack)
        model.setNote("  ", for: try row("Ari", in: model))
        stack.viewContext.processPendingChanges()
        #expect(stack.viewContext.insertedObjects.isEmpty)
        #expect(try recordCount(stack) == 0)

        model.setNote("Early pickup", for: try row("Ari", in: model))
        #expect(try row("Ari", in: model).note == "Early pickup")
        #expect(try recordCount(stack) == 1)
    }

    @Test("Sent only once an export that began after the last save has finished")
    func syncStatus() {
        typealias Line = AssistantSyncStatusView
        #expect(Line.status(hasUnsavedChanges: false, lastSave: 10, lastExportStart: 20, lastExportFailed: false)
            == .sent)
        #expect(Line.status(hasUnsavedChanges: false, lastSave: 20, lastExportStart: 10, lastExportFailed: false)
            == .sending)
        #expect(Line.status(hasUnsavedChanges: false, lastSave: 20, lastExportStart: 10, lastExportFailed: true)
            == .waitingForNetwork)
        #expect(Line.status(hasUnsavedChanges: true, lastSave: 10, lastExportStart: 20, lastExportFailed: false)
            == .sending)
    }

    @Test("The stack is rebuilt once, only when iCloud arrives after a start without it")
    func accountDecision() {
        let decide = AssistantBootstrapper.accountDecision
        // Started without an account, then it arrives: one rebuild.
        var step = decide(false, false, .noAccount)
        #expect(step == (true, false))
        step = decide(true, step.needsAccount, .available)
        #expect(step == (false, true))
        #expect(decide(true, step.needsAccount, .available) == (false, false))
        // Started with an account: never.
        step = decide(false, false, .available)
        #expect(step == (false, false))
        step = decide(true, step.needsAccount, .noAccount)
        #expect(decide(true, step.needsAccount, .available) == (false, false))
    }
}
