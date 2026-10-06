import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Sync and sharing bug hunt 2026-10-05, #6: the sync line's last save,
// export and import were recorded by the line's own listeners, so a Siri mark
// made with the app closed read "All marks sent", and an export finished
// during a visit to Restock left it on "Sending to iCloud…". They're recorded
// for the whole app now (`AssistantSyncRecord`). CloudKit's events can't be
// made in a test, so they're reported through `record(_:)`, which is all the
// event observer does.
@Suite("Assistant sync record")
@MainActor
struct AssistantSyncRecordTests {

    private typealias Line = AssistantSyncStatusView

    private let stack: CoreDataStack
    private let defaults: UserDefaults

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        defaults = AssistantTestSupport.makeDefaults()
    }

    private func export(started start: Date, succeeded: Bool = true) -> AssistantSyncRecord.FinishedEvent {
        .init(isExport: true, start: start, end: start.addingTimeInterval(1), succeeded: succeeded)
    }

    private func status(_ record: AssistantSyncRecord, waiting: Int = 0) -> Line.Status {
        Line.status(
            hasUnsavedChanges: false,
            lastSave: record.lastSave,
            lastExportStart: record.lastExportStart,
            lastExportFailed: record.lastExportFailed,
            waitingForShare: waiting
        )
    }

    @Test("Any save on the view context counts, with no sync line on screen")
    func saveIsRecorded() throws {
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        #expect(record.lastSave == 0)
        let mark = CDAttendanceRecord(context: stack.viewContext)
        mark.id = UUID()
        #expect(stack.viewContext.safeSave())
        #expect(record.lastSave > 0)
        #expect(defaults.double(forKey: AssistantSyncRecord.lastSharedSaveKey) == record.lastSave)
        #expect(status(record) == .sending)

        record.record(export(started: Date()))
        #expect(status(record) == .sent)
    }

    @Test("A failed export says not sent yet; a late event for an earlier export doesn't take the start back")
    func exportsAreRecorded() {
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        record.saved(at: Date(timeIntervalSince1970: 100))
        record.record(export(started: Date(timeIntervalSince1970: 50), succeeded: false))
        #expect(record.lastExportFailed)
        #expect(status(record) == .waitingForNetwork)

        record.record(export(started: Date(timeIntervalSince1970: 200)))
        #expect(!record.lastExportFailed)
        #expect(status(record) == .sent)
        record.record(export(started: Date(timeIntervalSince1970: 150)))
        #expect(record.lastExportStart == 200)
    }

    @Test("Only a successful import moves the class's last update")
    func importsAreRecorded() {
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        let end = Date(timeIntervalSince1970: 300)
        record.record(.init(isExport: false, start: end.addingTimeInterval(-5), end: end, succeeded: false))
        #expect(record.lastImportEnd == 0)
        record.record(.init(isExport: false, start: end.addingTimeInterval(-5), end: end, succeeded: true))
        #expect(record.lastImportEnd == 300)
        // An import doesn't touch the export's state.
        #expect(record.lastExportStart == 0)
    }

    @Test("The times are kept for the next launch, and go with the class")
    func keptAndForgotten() {
        let first = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        first.saved(at: Date(timeIntervalSince1970: 100))
        first.record(export(started: Date(timeIntervalSince1970: 50)))
        let next = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        #expect(next.lastSave == 100)
        #expect(next.lastExportStart == 50)
        #expect(status(next) == .sending)

        AssistantSyncRecord.forget(defaults: defaults)
        let afterLeave = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        #expect(afterLeave.lastSave == 0)
        #expect(status(afterLeave) == .sent)
    }

    @Test("Marks waiting to go into the share read as sending, even after an export")
    func waitingForTheShare() {
        #expect(Line.status(hasUnsavedChanges: false, lastSave: 10, lastExportStart: 20, lastExportFailed: false,
                            waitingForShare: 1) == .sending)
        #expect(Line.status(hasUnsavedChanges: false, lastSave: 10, lastExportStart: 20, lastExportFailed: true,
                            waitingForShare: 2) == .waitingForNetwork)
        #expect(Line.status(hasUnsavedChanges: false, lastSave: 10, lastExportStart: 20, lastExportFailed: false,
                            waitingForShare: 0) == .sent)
    }
}
