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

    private func launch(networkUsable: Bool? = nil) -> AssistantShareAttacher {
        AssistantShareAttacher(
            defaults: defaults, now: { [clock] in clock.now }, sleep: share.sleep, attempt: share.attempt,
            networkUsable: { networkUsable }
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
        #expect(!attacher.isOffline, "the last round reached iCloud, though nothing went in")
    }

    @Test("A retry asked for during a send that then fails tries again at once, not after the rest")
    func retryDuringPassIsKept() async {
        let attacher = launch()
        share.offline = true
        await attach(marks(1), with: attacher)
        #expect(share.attempts.count == 1)

        // The network comes back while a fresh mark's try is still out on
        // the old link, and that try fails.
        share.offline = false
        share.holdsNextAttempt = true
        share.refusesNextAttempt = true
        attacher.attach(marks(1), container: stack.container, context: context)
        while !share.isHolding { await Task.yield() }
        attacher.retryWaiting()
        share.release()
        await attacher.waitUntilIdle()

        #expect(share.attempts.count == 3, "the retry wasn't swallowed by the failed try's rest")
        #expect(attacher.pending.isEmpty)
    }

    @Test("A retry during a send that fails goes again without counting the failed try")
    func retryDuringPassDoesNotDoubleTheRest() async {
        let attacher = launch()
        share.offline = true
        await attach(marks(1), with: attacher)
        #expect(share.rests == [30])

        // Still offline: the phone locks while a fresh mark's try is out.
        share.holdsNextAttempt = true
        attacher.attach(marks(1), container: stack.container, context: context)
        while !share.isHolding { await Task.yield() }
        attacher.retryWaiting()
        share.release()
        await attacher.waitUntilIdle()

        #expect(share.attempts.count == 3, "the retry went again at once")
        #expect(share.rests == [30, 60], "the try the retry cut short isn't counted as a failure of its own")
    }

    @Test("A round that puts some marks in before losing the connection isn't offline")
    func partlySentRoundIsNotOffline() async {
        let attacher = launch()
        share.dropsConnectionAfter = 1
        await attach(marks(2), with: attacher)
        #expect(attacher.pending.count == 1)
        #expect(!attacher.isOffline, "a mark reached iCloud in this round")
    }

    @Test("Locking tries resting marks only while offline or once the rest is over")
    func lockRetriesOnlyWithAChance() async {
        let attacher = launch()
        share.refusesEverything = true
        await attach(marks(1), with: attacher)
        share.refusesEverything = false
        #expect(!attacher.waitingHaveAChance)
        attacher.retryWaitingIfAChance()
        await attacher.waitUntilIdle()
        #expect(share.attempts.count == 1, "a mark resting after a refusal waits out its rest")

        clock.advance(61)
        #expect(attacher.waitingHaveAChance)
        attacher.retryWaitingIfAChance()
        await attacher.waitUntilIdle()
        #expect(share.attempts.count == 2)
        #expect(attacher.pending.isEmpty)

        share.offline = true
        await attach(marks(1), with: attacher)
        share.offline = false
        #expect(attacher.waitingHaveAChance, "offline marks are worth a try at any lock")
        attacher.retryWaitingIfAChance()
        await attacher.waitUntilIdle()
        #expect(attacher.pending.isEmpty)
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
        func line(
            waiting: Int, offline: Bool, exported: Double = 1, network: AssistantNetworkWatch.PathState? = nil
        ) -> AssistantSyncStatusView.Status {
            AssistantSyncStatusView.status(
                hasUnsavedChanges: false, lastEditSave: 2, lastExportStart: exported,
                lastExportFailure: nil, waitingForShare: waiting, shareOffline: offline, network: network
            )
        }
        #expect(line(waiting: 1, offline: true) == .offline)
        #expect(line(waiting: 1, offline: true, network: .init(usable: true, interface: .wifi))
            == .troubleReachingICloud, "on a network, iCloud is what isn't reached")
        #expect(line(waiting: 1, offline: false) == .sending)
        #expect(line(waiting: 0, offline: true, exported: 3) == .sent)
    }

    // 2026-10-22: Nicole's marks sat all morning with every share call
    // failing the same way on a working network, and only turning Wi-Fi off
    // and on moved them. The share step now says when sending looks stalled,
    // and the bootstrapper restarts the stack (`sendStalled`).
    @Test("Two passes in a row that can't reach iCloud on a usable network say sending has stalled")
    func stallIsToldOnAUsableNetwork() async throws {
        let stalled = Stalls()
        let attacher = launch(networkUsable: true)
        attacher.onStalled = { stalled.count += 1 }
        share.offline = true
        await attach(marks(1), with: attacher)
        #expect(stalled.count == 0, "one failure is a blip on any link")
        await attach(marks(1), with: attacher)
        #expect(stalled.count == 1)
        await attach(marks(1), with: attacher)
        #expect(stalled.count == 2, "told after every such round; the bootstrapper decides how often it acts")

        // A rebuilt stack starts the count over.
        let rebuilt = try AssistantTestSupport.makeStack()
        attacher.flush(container: rebuilt.container, context: rebuilt.viewContext)
        await attacher.waitUntilIdle()
        #expect(stalled.count == 2, "the first pass on the new stack isn't a stall")
    }

    @Test("Offline, before the first path, or with a mark going in, failures are not a stall")
    func noStallWithoutAUsableNetwork() async {
        for usable in [false, nil] as [Bool?] {
            let stalled = Stalls()
            let attacher = launch(networkUsable: usable)
            attacher.onStalled = { stalled.count += 1 }
            share.offline = true
            for _ in 0..<3 { await attach(marks(1), with: attacher) }
            #expect(stalled.count == 0, "no network, or none known: that's being offline")
            attacher.forgetWaiting()
            share.offline = false
        }

        let stalled = Stalls()
        let attacher = launch(networkUsable: true)
        attacher.onStalled = { stalled.count += 1 }
        share.offline = true
        await attach(marks(1), with: attacher)
        share.offline = false
        share.dropsConnectionAfter = 1
        await attach(marks(2), with: attacher)
        #expect(stalled.count == 0, "a mark reached iCloud this round")

        #expect(AssistantShareAttacher.sendLooksStalled(networkFailuresInARow: 2, networkUsable: true))
        #expect(!AssistantShareAttacher.sendLooksStalled(networkFailuresInARow: 1, networkUsable: true))
        #expect(!AssistantShareAttacher.sendLooksStalled(networkFailuresInARow: 2, networkUsable: false))
        #expect(!AssistantShareAttacher.sendLooksStalled(networkFailuresInARow: 2, networkUsable: nil))
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

/// How many times the attacher said sending looked stalled.
@MainActor
private final class Stalls {
    var count = 0
}

@MainActor
private final class OfflineClock {
    private(set) var now = Date()
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}
