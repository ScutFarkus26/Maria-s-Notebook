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
//
// 2026-10-22: a new mark is the share step's to count, and only an edit or a
// removal waits for Core Data's upload; a failed export says offline only
// when the network was the reason; and the network the phone is on tells
// "back online" from "trouble reaching iCloud".
@Suite("Assistant sync record")
@MainActor
struct AssistantSyncRecordTests {

    private typealias Line = AssistantSyncStatusView
    private typealias Path = AssistantNetworkWatch.PathState

    private let stack: CoreDataStack
    private let defaults: UserDefaults

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        defaults = AssistantTestSupport.makeDefaults()
    }

    private func export(
        started start: Date, succeeded: Bool = true, noConnection: Bool = false
    ) -> AssistantSyncRecord.FinishedEvent {
        .init(isExport: true, start: start, end: start.addingTimeInterval(1), succeeded: succeeded,
              noConnection: noConnection)
    }

    private func status(_ record: AssistantSyncRecord, waiting: Int = 0, network: Path? = nil) -> Line.Status {
        Line.status(
            hasUnsavedChanges: false,
            lastEditSave: record.lastEditSave,
            lastExportStart: record.lastExportStart,
            lastExportFailure: record.lastExportFailure,
            waitingForShare: waiting,
            network: network
        )
    }

    @Test("A new mark is the share step's to count; an edit on the view context counts, with no sync line on screen")
    func saveIsRecorded() throws {
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        #expect(record.lastEditSave == 0)
        let mark = CDAttendanceRecord(context: stack.viewContext)
        mark.id = UUID()
        #expect(stack.viewContext.safeSave())
        #expect(record.lastEditSave == 0, "a new mark goes by the share step, which counts it")
        #expect(status(record) == .sent)
        #expect(status(record, waiting: 1) == .sending)

        mark.note = "Early pickup"
        #expect(stack.viewContext.safeSave())
        #expect(record.lastEditSave > 0)
        #expect(defaults.double(forKey: AssistantSyncRecord.lastSharedEditSaveKey) == record.lastEditSave)
        #expect(status(record) == .sending)

        record.record(export(started: Date()))
        #expect(status(record) == .sent)
    }

    @Test("A failed export says offline only when the network was why; a late event for an earlier export doesn't take the start back")
    func exportsAreRecorded() {
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        record.saved(at: Date(timeIntervalSince1970: 100))
        record.record(export(started: Date(timeIntervalSince1970: 50), succeeded: false))
        #expect(record.lastExportFailure == .other)
        #expect(status(record) == .tryingAgain)
        record.record(export(started: Date(timeIntervalSince1970: 60), succeeded: false, noConnection: true))
        #expect(record.lastExportFailure == .network)
        #expect(status(record) == .offline)

        record.record(export(started: Date(timeIntervalSince1970: 200)))
        #expect(record.lastExportFailure == nil)
        #expect(status(record) == .sent)
        record.record(export(started: Date(timeIntervalSince1970: 150)))
        #expect(record.lastExportStart == 200)
    }

    @Test("A failed export with no edit waiting for the upload changes nothing on the line")
    func failureWithoutAnEdit() {
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        record.record(export(started: Date(timeIntervalSince1970: 50), succeeded: false, noConnection: true))
        #expect(record.lastExportFailure == .network)
        #expect(status(record) == .sent)
        #expect(status(record, waiting: 1) == .sending, "the share step says for itself whether it's offline")
    }

    // The line names no culprit on a network: build 024 blamed the Wi-Fi,
    // a cause that was never shown (2026-10-22).
    @Test("The network the phone is on tells back online from trouble reaching iCloud, blaming nothing")
    func networkWording() {
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        record.saved(at: Date(timeIntervalSince1970: 100))
        record.record(export(started: Date(timeIntervalSince1970: 50), succeeded: false, noConnection: true))
        #expect(status(record) == .offline, "before the first path, nothing better is known")
        #expect(status(record, network: Path(usable: false, interface: .other)) == .offline)
        #expect(status(record, network: Path(usable: true, interface: .wifi)) == .troubleReachingICloud)
        #expect(status(record, network: Path(usable: true, interface: .cellular)) == .troubleReachingICloud)

        #expect(Line.troubleReachingICloudMessage == "Not sent yet. Having trouble reaching iCloud. Trying again.")
        #expect(!Line.troubleReachingICloudMessage.contains("Wi-Fi"), "the network isn't blamed")
        #expect(Line.offlineMessage == "Not sent yet. They'll go when you're back online.")
        #expect(Line.tryingAgainMessage == "Couldn't send yet. Trying again.")
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

    @Test("The times are kept for the next launch, and go with the class; the old every-save time is dropped")
    func keptAndForgotten() {
        let retiredKey = CloudKitEnvironment.scoped("Assistant.lastSharedSave")
        defaults.set(100.0, forKey: retiredKey)
        let first = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        #expect(defaults.object(forKey: retiredKey) == nil)
        #expect(first.lastEditSave == 0, "a save from before new marks stopped counting doesn't hold the line")
        first.saved(at: Date(timeIntervalSince1970: 100))
        first.record(export(started: Date(timeIntervalSince1970: 50)))
        let next = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        #expect(next.lastEditSave == 100)
        #expect(next.lastExportStart == 50)
        #expect(status(next) == .sending)

        AssistantSyncRecord.forget(defaults: defaults)
        let afterLeave = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        #expect(afterLeave.lastEditSave == 0)
        #expect(status(afterLeave) == .sent)
    }

    @Test("Marks waiting to go into the share read as sending, even after an export; offline only when the share step says so")
    func waitingForTheShare() {
        func line(waiting: Int, failure: AssistantSyncRecord.ExportFailure? = nil, offline: Bool = false) -> Line.Status {
            Line.status(hasUnsavedChanges: false, lastEditSave: 10, lastExportStart: 20, lastExportFailure: failure,
                        waitingForShare: waiting, shareOffline: offline)
        }
        #expect(line(waiting: 1) == .sending)
        #expect(line(waiting: 2, failure: .network) == .sending, "the upload's failure isn't the share step's")
        #expect(line(waiting: 2, offline: true) == .offline)
        #expect(line(waiting: 0) == .sent)
        #expect(line(waiting: 0, offline: true) == .sent)
    }

    @Test("A successful export or import says iCloud can be reached; a failed one doesn't")
    func syncProvesOnline() {
        let record = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        let heard = Heard()
        record.onSharedStoreSynced = { heard.count += 1 }
        record.record(export(started: Date(), succeeded: false))
        #expect(heard.count == 0)
        record.record(export(started: Date()))
        record.record(.init(isExport: false, start: Date(), end: Date(), succeeded: true))
        #expect(heard.count == 2)
    }
}

/// How many times a callback was heard.
@MainActor
private final class Heard {
    var count = 0
}
