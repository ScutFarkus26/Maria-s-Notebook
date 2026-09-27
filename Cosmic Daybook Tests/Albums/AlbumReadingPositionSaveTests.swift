import Foundation
import Testing
@testable import CosmicDaybook

/// The album reader writes the reading position once page turns have settled
/// for 1.5 s, one write however many turns. It now also writes a waiting turn
/// at once when its scene goes to the background, so an iOS kill there no
/// longer loses where the guide was; on closing it drops the waiting turn and
/// writes the page it is on, as it always has. The debouncer is the reader's
/// own (`AlbumSaveDebouncer`, keyed by album), on a clock the test moves.
@Suite("Album reading position saves")
@MainActor
struct AlbumReadingPositionSaveTests {

    private static let album = "Math Album.pdf"

    private static func at(_ milliseconds: Int) -> ManualTestClock.Instant {
        ManualTestClock.Instant(offset: .milliseconds(milliseconds))
    }

    /// The pages the reader wrote as its position, in order.
    private final class Positions {
        var written: [Int] = []
    }

    private static func reader(_ clock: ManualTestClock) -> AlbumSaveDebouncer<String, ManualTestClock> {
        AlbumSaveDebouncer<String, ManualTestClock>(delay: AlbumDetailView.positionSaveDelay, clock: clock)
    }

    /// A page turn, scheduled as `AlbumDetailView.schedulePositionSave` does.
    private static func turn(to page: Int, _ saves: AlbumSaveDebouncer<String, ManualTestClock>,
                             _ positions: Positions) {
        saves.schedule(album) { positions.written.append(page) }
    }

    @Test("Page turns write once, 1.5 s after the last, the page the guide settled on")
    func turnsSettleIntoOneWrite() async {
        #expect(AlbumDetailView.positionSaveDelay == .milliseconds(1500))
        let clock = ManualTestClock()
        let saves = Self.reader(clock)
        let positions = Positions()

        // Each turn replaces the wait before it (the test lets each one fall
        // asleep first, so the clock holds only the live one).
        Self.turn(to: 3, saves, positions)
        #expect(await AlbumTestSupport.waitUntil { clock.pendingDeadlines == [Self.at(1500)] })
        clock.advance(by: .milliseconds(600))
        Self.turn(to: 4, saves, positions)
        #expect(await AlbumTestSupport.waitUntil { clock.pendingDeadlines == [Self.at(2100)] })
        clock.advance(by: .milliseconds(600))
        Self.turn(to: 5, saves, positions)
        #expect(await AlbumTestSupport.waitUntil { clock.pendingDeadlines == [Self.at(2700)] })
        clock.advance(by: .milliseconds(1499))
        #expect(positions.written.isEmpty)
        clock.advance(by: .milliseconds(1))
        #expect(await AlbumTestSupport.waitUntil { positions.written == [5] })
        #expect(saves.waitingKeys.isEmpty)
    }

    @Test("Going to the background writes a waiting turn at once, and only once")
    func backgroundWritesAtOnce() async {
        let clock = ManualTestClock()
        let saves = Self.reader(clock)
        let positions = Positions()

        Self.turn(to: 7, saves, positions)
        clock.advance(by: .milliseconds(200))
        // What the reader does when its scene goes to the background.
        saves.flush()
        #expect(positions.written == [7])
        #expect(saves.waitingKeys.isEmpty)

        // The flushed wait ends without writing again; a later turn writes alone.
        Self.turn(to: 8, saves, positions)
        clock.advance(by: .seconds(2))
        #expect(await AlbumTestSupport.waitUntil { positions.written.count == 2 })
        #expect(positions.written == [7, 8])
    }

    @Test("Going to the background with no turn waiting writes nothing")
    func backgroundWithNothingWaiting() async {
        let clock = ManualTestClock()
        let saves = Self.reader(clock)
        let positions = Positions()

        Self.turn(to: 2, saves, positions)
        clock.advance(by: .milliseconds(1500))
        #expect(await AlbumTestSupport.waitUntil { positions.written == [2] })
        saves.flush()
        #expect(positions.written == [2])
    }

    @Test("Closing drops the waiting turn unwritten; the reader writes the page it is on itself")
    func closingDropsTheWaitingTurn() async {
        let clock = ManualTestClock()
        let saves = Self.reader(clock)
        let positions = Positions()

        Self.turn(to: 9, saves, positions)
        // What the reader does on disappearing, before writing `currentPage`.
        saves.cancelAll()
        #expect(saves.waitingKeys.isEmpty)
        Self.turn(to: 10, saves, positions)
        clock.advance(by: .seconds(2))
        #expect(await AlbumTestSupport.waitUntil { positions.written.count == 1 })
        #expect(positions.written == [10])
    }
}
