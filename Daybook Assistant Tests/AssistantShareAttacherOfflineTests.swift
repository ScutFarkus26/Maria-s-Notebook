import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The attacher when iCloud can't be reached or asks to wait: a short rest
// that grows on its own count, CloudKit's wait kept through early retries,
// and the offline flag the sync line reads. Same stand-ins as
// `AssistantShareAttacherTests` (`FakeShare`).
@Suite("Assistant share attacher offline")
@MainActor
struct AssistantShareAttacherOfflineTests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    private let share = FakeShare()
    private let clock = OfflineClock()

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        defaults = AssistantTestSupport.makeDefaults()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func launch() -> AssistantShareAttacher {
        AssistantShareAttacher(
            defaults: defaults, now: { [clock] in clock.now }, sleep: share.sleep, attempt: share.attempt
        )
    }

    private func marks(_ count: Int) -> [NSManagedObjectID] {
        let records = (0..<count).map { _ in
            let record = CDAttendanceRecord(context: context)
            record.id = UUID()
            return record
        }
        #expect(context.safeSave())
        return records.map(\.objectID)
    }

    private func attach(_ ids: [NSManagedObjectID], with attacher: AssistantShareAttacher) async {
        attacher.attach(ids, container: stack.container, context: context)
        await attacher.waitUntilIdle()
    }

    @Test("Offline, the rest is 30 seconds, doubling to two minutes")
    func offlineRestSchedule() {
        let rests = (1...4).map { AssistantShareAttacher.rest(afterFailures: $0, noConnection: true) }
        #expect(rests == [30, 60, 120, 120])
        #expect(AssistantShareAttacher.rest(afterFailures: 2, noConnection: false) == 120)
    }

    @Test("A pass that can't reach iCloud says so, rests briefly, and a mark that goes in clears it")
    func offlineFlagAndShortRest() async {
        let attacher = launch()
        share.offline = true
        await attach(marks(1), with: attacher)
        #expect(attacher.isOffline)
        #expect(share.rests == [30])

        share.offline = false
        await attach(marks(1), with: attacher)
        #expect(!attacher.isOffline)
    }

    @Test("Network failures and refusals back off on their own counts")
    func restCountsAreSeparate() async {
        let attacher = launch()
        share.offline = true
        for _ in 0..<3 { await attach(marks(1), with: attacher) }
        share.offline = false
        share.refusesEverything = true
        await attach(marks(1), with: attacher)
        #expect(share.rests == [30, 60, 120, 60])
        // A refusal isn't "offline": the line goes back to "Sending…".
        await attach(marks(1), with: attacher)
        #expect(attacher.isOffline, "no mark has gone in since the network failures")
    }

    @Test("CloudKit's wait holds even when something asks for a retry; a new mark is still tried")
    func retryAfterHolds() async {
        let attacher = launch()
        let first = marks(1)
        share.throttledFor = 300
        await attach(first, with: attacher)
        #expect(share.rests == [300])
        #expect(!attacher.isOffline)

        share.throttledFor = nil
        clock.advance(100)
        attacher.retryWaiting()
        await attacher.waitUntilIdle()
        #expect(share.attempts == [first], "coming back or the network returning doesn't cut CloudKit's wait short")

        let fresh = marks(1)
        await attach(fresh, with: attacher)
        #expect(share.attempts == [first, fresh], "a mark she just tapped goes at once")
        #expect(attacher.pending == first.map { $0.uriRepresentation() })

        clock.advance(200)
        attacher.retryWaiting()
        await attacher.waitUntilIdle()
        #expect(share.attempts.last == first)
        #expect(attacher.pending.isEmpty)
    }

    @Test("The sync line says marks wait for the network only while some wait and the share step is offline")
    func lineSaysOffline() {
        func line(waiting: Int, offline: Bool, exported: Double = 1) -> AssistantSyncStatusView.Status {
            AssistantSyncStatusView.status(
                hasUnsavedChanges: false, lastSave: 2, lastExportStart: exported,
                lastExportFailed: false, waitingForShare: waiting, shareOffline: offline
            )
        }
        #expect(line(waiting: 1, offline: true) == .waitingForNetwork)
        #expect(line(waiting: 1, offline: false) == .sending)
        #expect(line(waiting: 0, offline: true, exported: 3) == .sent)
    }

    @Test("A rebuilt stack and Leave both clear the offline flag")
    func offlineClears() async throws {
        let attacher = launch()
        share.offline = true
        await attach(marks(1), with: attacher)
        #expect(attacher.isOffline)
        let rebuilt = try AssistantTestSupport.makeStack()
        attacher.flush(container: rebuilt.container, context: rebuilt.viewContext)
        await attacher.waitUntilIdle()
        #expect(!attacher.isOffline)

        await attach(marks(1), with: attacher)
        #expect(attacher.isOffline)
        attacher.forgetWaiting()
        #expect(!attacher.isOffline)
    }
}

@MainActor
private final class OfflineClock {
    private(set) var now = Date()
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}
