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

    // Logic-break sweep 2026-09-29, F7. Leave and Rebuild from iCloud kept
    // the Late days, Siri's Undo and the sync line's times of the class
    // they took off the iPhone.
    @Test("Leaving or rebuilding forgets Late days, Siri's Undo and the sync line's times")
    func forgetsClassroomState() throws {
        let defaults = AssistantTestSupport.makeDefaults()
        let day = try AssistantTestSupport.day("2031-01-06")
        let syncKeys = [
            AssistantSyncStatusView.lastSharedSaveKey,
            AssistantSyncStatusView.lastSharedExportStartKey,
            AssistantSyncStatusView.lastSharedImportEndKey
        ]
        AttendanceLatePhase.setLate(true, on: day, defaults: defaults)
        SiriAttendanceChange(day: day, marks: [], summary: "closing arrival", closedArrival: true)
            .remember(defaults: defaults)
        for key in syncKeys { defaults.set(20.0, forKey: key) }

        AssistantClassroomLocalState.forget(defaults: defaults)
        #expect(!AttendanceLatePhase.isLate(on: day, defaults: defaults))
        #expect(SiriAttendanceChange.last(defaults: defaults) == nil)
        for key in syncKeys { #expect(defaults.object(forKey: key) == nil) }
    }

    @Test("The stack is rebuilt once, only when iCloud arrives after a start without it")
    func accountDecision() {
        let decide = AssistantBootstrapper.accountDecision
        typealias Decision = AssistantBootstrapper.AccountDecision
        let waits = Decision(needsAccount: true), fine = Decision(needsAccount: false)
        let rebuild = Decision(needsAccount: false, rebuild: true)
        // Started without an account, then it arrives: one rebuild.
        var step = decide(false, false, .noAccount)
        #expect(step == waits)
        step = decide(true, step.needsAccount, .available)
        #expect(step == rebuild)
        #expect(decide(true, step.needsAccount, .available) == fine)
        // Started with an account: never.
        step = decide(false, false, .available)
        #expect(step == fine)
        step = decide(true, step.needsAccount, .noAccount)
        #expect(decide(true, step.needsAccount, .available) == fine)
        // A restricted account can't set up sharing either.
        #expect(decide(false, false, .restricted) == waits)
    }

    @Test("A first check that can't tell arms no rebuild; the next one decides")
    func accountDecisionUndecided() {
        let decide = AssistantBootstrapper.accountDecision
        typealias Decision = AssistantBootstrapper.AccountDecision
        let first = decide(false, false, .couldNotDetermine)
        #expect(first == Decision(needsAccount: false, decided: false))
        // Then the account answers as available: nothing to rebuild.
        #expect(decide(first.decided, first.needsAccount, .available) == Decision(needsAccount: false))
        // Or as missing: the stack waits for it, as after a start without one.
        let missing = decide(first.decided, first.needsAccount, .noAccount)
        #expect(missing == Decision(needsAccount: true))
        #expect(decide(missing.decided, missing.needsAccount, .available).rebuild)
    }

    // CloudKit won't set up the container while the account is temporarily
    // unavailable ("Unable to initialize without a valid iCloud account",
    // simulator log 2026-09-29), so that start needs the rebuild too.
    @Test("A start while iCloud is temporarily unavailable rebuilds once the account is back")
    func accountDecisionTemporarilyUnavailable() {
        let decide = AssistantBootstrapper.accountDecision
        let first = decide(false, false, .temporarilyUnavailable)
        #expect(first == AssistantBootstrapper.AccountDecision(needsAccount: true))
        #expect(decide(true, first.needsAccount, .available).rebuild)
    }
}
