import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The retry queue for putting the Assistant's new marks into the classroom
// share, run on an in-memory stack. The real attempt needs a classroom share,
// so each test stands in a `FakeShare` that refuses what it's told to, a
// clock it moves by hand, and a sleep that only notes each rest (a retry
// fires only where a test says so).
@Suite("Assistant share attacher")
@MainActor
struct AssistantShareAttacherTests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    private let share = FakeShare()
    private let clock = Clock()

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        defaults = AssistantTestSupport.makeDefaults()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    /// A new attacher on the same defaults is the next launch.
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

    private func flush(_ attacher: AssistantShareAttacher) async {
        attacher.flush(container: stack.container, context: context)
        await attacher.waitUntilIdle()
    }

    @Test("A mark that goes in leaves nothing waiting")
    func attached() async {
        let attacher = launch()
        let ids = marks(2)
        await attach(ids, with: attacher)
        #expect(share.attempts == [ids])
        #expect(attacher.pending.isEmpty)
    }

    @Test("A mark CloudKit refuses waits, and goes in at the next launch")
    func refusedWaitsForLaunch() async {
        let ids = marks(2)
        share.refuses = [ids[0]]
        let first = launch()
        await attach(ids, with: first)
        #expect(first.pending == [ids[0].uriRepresentation()])

        share.refuses = []
        let next = launch()
        await flush(next)
        #expect(share.attempts.last == [ids[0]])
        #expect(next.pending.isEmpty)
    }

    @Test("With no share yet, every mark waits")
    func noShareYet() async {
        let attacher = launch()
        let ids = marks(3)
        share.refusesEverything = true
        await attach(ids, with: attacher)
        #expect(attacher.pending == ids.map { $0.uriRepresentation() })
    }

    @Test("While CloudKit keeps refusing, waiting marks rest, but a new mark is always tried")
    func backlogRests() async {
        let attacher = launch()
        let (refused, second, third) = { let ids = marks(3); return (ids[0], ids[1], ids[2]) }()
        share.refusesEverything = true
        await attach([refused], with: attacher)

        clock.advance(AssistantShareAttacher.rest(afterFailures: 1) - 1)
        await attach([second], with: attacher)
        #expect(share.attempts.last == [second])
        #expect(attacher.pending == [refused, second].map { $0.uriRepresentation() })

        share.refusesEverything = false
        clock.advance(AssistantShareAttacher.rest(afterFailures: 2) + 1)
        await attach([third], with: attacher)
        #expect(share.attempts.last == [refused, second, third])
        #expect(attacher.pending.isEmpty)
    }

    @Test("A new mark that goes in ends the rest: the waiting marks go in right behind it")
    func successEndsTheRest() async {
        let attacher = launch()
        let (refused, second) = { let ids = marks(2); return (ids[0], ids[1]) }()
        share.refuses = [refused]
        await attach([refused], with: attacher)
        share.refuses = []

        await attach([second], with: attacher)
        #expect(share.attempts == [[refused], [second], [refused]])
        #expect(attacher.pending.isEmpty)
    }

    @Test("A mark refused even when the rest ends early waits out the full rest, then is tried again")
    func stillRefusedRestsAgain() async {
        let attacher = launch()
        let (refused, second, third) = { let ids = marks(3); return (ids[0], ids[1], ids[2]) }()
        share.refuses = [refused]
        await attach([refused], with: attacher)
        await attach([second], with: attacher)
        #expect(share.attempts == [[refused], [second], [refused]])

        // Resting again, and not ended early a second time: the next new mark goes alone.
        await attach([third], with: attacher)
        #expect(share.attempts.last == [third])
        #expect(attacher.pending == [refused.uriRepresentation()])

        share.refuses = []
        clock.advance(AssistantShareAttacher.rest(afterFailures: 2) + 1)
        let fourth = marks(1)[0]
        await attach([fourth], with: attacher)
        #expect(share.attempts.last == [refused, fourth])
        #expect(attacher.pending.isEmpty)
    }

    @Test("A flush during the pause tries nothing")
    func flushDuringPause() async {
        let attacher = launch()
        let ids = marks(1)
        share.refuses = Set(ids)
        await attach(ids, with: attacher)
        await flush(attacher)
        #expect(share.attempts.count == 1)
        #expect(attacher.pending.count == 1)
    }

    @Test("One pass at a time: a mark saved during a pass gets the next one")
    func onePassAtATime() async {
        let attacher = launch()
        let ids = marks(2)
        share.holdsNextAttempt = true
        attacher.attach([ids[0]], container: stack.container, context: context)
        while !share.isHolding { await Task.yield() }

        attacher.attach([ids[1]], container: stack.container, context: context)
        #expect(share.attempts == [[ids[0]]])
        share.release()
        await attacher.waitUntilIdle()

        #expect(share.attempts == [[ids[0]], [ids[1]]])
        #expect(share.mostAtOnce == 1)
        #expect(attacher.pending.isEmpty)
    }

    @Test("A mark refused while another was saved mid-pass keeps both right")
    func refusedDuringPass() async {
        let attacher = launch()
        let ids = marks(2)
        share.refuses = [ids[0]]
        share.holdsNextAttempt = true
        attacher.attach([ids[0]], container: stack.container, context: context)
        while !share.isHolding { await Task.yield() }

        attacher.attach([ids[1]], container: stack.container, context: context)
        share.release()
        await attacher.waitUntilIdle()

        // The second pass tries only the new mark; it goes in, so the refused
        // one is tried once more right after, and is refused again.
        #expect(share.attempts == [[ids[0]], [ids[1]], [ids[0]]])
        #expect(attacher.pending == [ids[0].uriRepresentation()])
    }

    @Test("A deleted mark drops out of the list without a try")
    func deletedMark() async {
        let ids = marks(1)
        share.refuses = Set(ids)
        await attach(ids, with: launch())
        context.delete(context.object(with: ids[0]))
        #expect(context.safeSave())

        let next = launch()
        await flush(next)
        #expect(share.attempts.count == 1)
        #expect(next.pending.isEmpty)
    }

    @Test("The rest is a minute, doubles with each failure in a row up to ten, and starts over after a success")
    func restGrows() async {
        let attacher = launch()
        let ids = marks(7)
        share.refusesEverything = true
        for id in ids.prefix(6) {
            await attach([id], with: attacher)
        }
        #expect(share.rests == [60, 120, 240, 480, 600, 600])

        share.refusesEverything = false
        await attach([ids[6]], with: attacher)
        share.refusesEverything = true
        await attach(marks(1), with: attacher)
        #expect(share.rests.last == 60)
    }

    @Test("When the rest ends, the waiting marks are tried without a tap")
    func retriesWhenTheRestEnds() async {
        let attacher = launch()
        let ids = marks(1)
        share.refuses = Set(ids)
        share.retriesAfterRest = true
        attacher.attach(ids, container: stack.container, context: context)
        for _ in 0..<1_000 where share.attempts.count < 2 { await Task.yield() }
        await attacher.waitUntilIdle()

        #expect(share.attempts == [ids, ids])
        #expect(attacher.pending.isEmpty)
    }

    @Test("Coming back to the app tries the waiting marks, even mid-rest")
    func retriesOnReturn() async {
        let attacher = launch()
        let ids = marks(1)
        share.refuses = Set(ids)
        await attach(ids, with: attacher)
        share.refuses = []

        attacher.retryWaiting()
        await attacher.waitUntilIdle()
        #expect(share.attempts == [ids, ids])
        #expect(attacher.pending.isEmpty)

        // Nothing waiting: nothing tried.
        attacher.retryWaiting()
        await attacher.waitUntilIdle()
        #expect(share.attempts.count == 2)
    }

    // Logic-break sweep 2026-09-29, F6. The attach dropped CloudKit's
    // "mirroring stopped" signal and returned only the failed marks, so the
    // queue kept retrying on a container where every `share(_:to:)` raises
    // an exception no catch traps.
    @Test("Once mirroring stops, nothing is tried again on that stack; the marks wait for a relaunch")
    func mirroringStopped() async {
        let attacher = launch()
        let ids = marks(2)
        share.stopsMirroringNextAttempt = true
        await attach([ids[0]], with: attacher)
        #expect(share.attempts == [[ids[0]]])
        #expect(share.rests.isEmpty)

        // A new mark, a flush and coming back to the app all try nothing.
        await attach([ids[1]], with: attacher)
        await flush(attacher)
        attacher.retryWaiting()
        await attacher.waitUntilIdle()
        #expect(share.attempts == [[ids[0]]])
        #expect(attacher.pending == ids.map { $0.uriRepresentation() })

        // The next launch's container starts afresh and sends them.
        let next = launch()
        await flush(next)
        #expect(share.attempts.last == ids)
        #expect(next.pending.isEmpty)
    }

    @Test("The list keeps the newest 500")
    func cap() async {
        let attacher = launch()
        let ids = marks(501)
        share.refusesEverything = true
        await attach(ids, with: attacher)
        #expect(attacher.pending.count == 500)
        #expect(attacher.pending.first == ids[1].uriRepresentation())
        #expect(attacher.pending.last == ids[500].uriRepresentation())
    }
}

/// Stands in for the classroom share: records every attempt, refuses what
/// it's told to, and can hold one attempt open.
@MainActor
final class FakeShare {
    var refuses: Set<NSManagedObjectID> = []
    var refusesEverything = false
    var holdsNextAttempt = false
    /// Refuses everything in the next attempt only.
    var refusesNextAttempt = false
    /// The next attempt reports CloudKit mirroring stopped, refusing all.
    var stopsMirroringNextAttempt = false
    /// Whether a rest's sleep returns (so the retry runs, and CloudKit is
    /// back by then) or is cancelled.
    var retriesAfterRest = false
    private(set) var attempts: [[NSManagedObjectID]] = []
    /// The context each attempt was given.
    private(set) var contexts: [NSManagedObjectContext] = []
    private(set) var rests: [TimeInterval] = []
    private(set) var mostAtOnce = 0
    private var running = 0
    private var held: CheckedContinuation<Void, Never>?

    var isHolding: Bool { held != nil }

    var attempt: AssistantShareAttacher.Attempt {
        { [self] ids, _, context in
            contexts.append(context)
            return await self.take(ids)
        }
    }

    var sleep: AssistantShareAttacher.Sleep {
        { [self] seconds in
            rests.append(seconds)
            if retriesAfterRest {
                retriesAfterRest = false
                refuses = []
                refusesEverything = false
            } else {
                throw CancellationError()
            }
        }
    }

    func release() {
        held?.resume()
        held = nil
    }

    private func take(_ ids: [NSManagedObjectID]) async -> CDAttendanceStore.ShareAttachResult {
        attempts.append(ids)
        running += 1
        mostAtOnce = max(mostAtOnce, running)
        if holdsNextAttempt {
            holdsNextAttempt = false
            await withCheckedContinuation { held = $0 }
        }
        running -= 1
        if stopsMirroringNextAttempt {
            stopsMirroringNextAttempt = false
            return .init(left: ids, mirroringStopped: true)
        }
        if refusesNextAttempt {
            refusesNextAttempt = false
            return .init(left: ids)
        }
        return .init(left: refusesEverything ? ids : ids.filter(refuses.contains))
    }
}

@MainActor
private final class Clock {
    private(set) var now = Date()
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}
