import Foundation
import Testing
@testable import Daybook_Assistant

// The network watch that tries waiting marks when the network comes back or
// changes. `NWPath` can't be made in a test, so paths come in as a stream of
// `PathState`s, with a short settle time.
@Suite("Assistant network watch", .serialized)
@MainActor
struct AssistantNetworkWatchTests {

    private typealias Path = AssistantNetworkWatch.PathState
    private let wifi = Path(usable: true, interface: .wifi)
    private let cellular = Path(usable: true, interface: .cellular)
    private let offline = Path(usable: false, interface: .other)
    private let settled: Duration = .milliseconds(800)

    @Test("Back online, or onto another kind of link, retries; the first path, the same link and going offline don't")
    func decisions() {
        #expect(!AssistantNetworkWatch.shouldRetry(from: nil, to: wifi))
        #expect(AssistantNetworkWatch.shouldRetry(from: offline, to: wifi))
        #expect(AssistantNetworkWatch.shouldRetry(from: wifi, to: cellular))
        #expect(AssistantNetworkWatch.shouldRetry(from: cellular, to: wifi))
        #expect(!AssistantNetworkWatch.shouldRetry(from: wifi, to: wifi))
        #expect(!AssistantNetworkWatch.shouldRetry(from: wifi, to: offline))
    }

    @Test("Changes within the settle time make one retry; a link gone before it settles makes none",
          .timeLimit(.minutes(1)))
    func settles() async throws {
        let (paths, feed) = AsyncStream.makeStream(of: Path.self)
        let retries = Retries()
        let watch = AssistantNetworkWatch(paths: paths, settle: .milliseconds(200)) { retries.count += 1 }

        feed.yield(wifi) // the first path only sets the scene
        feed.yield(offline)
        feed.yield(wifi) // back online…
        feed.yield(cellular) // …and onto cellular, within the settle time
        try await Task.sleep(for: settled)
        #expect(retries.count == 1)

        feed.yield(offline)
        feed.yield(wifi)
        feed.yield(offline) // gone again before it settled
        try await Task.sleep(for: settled)
        #expect(retries.count == 1)

        feed.yield(cellular)
        try await Task.sleep(for: settled)
        #expect(retries.count == 2)

        watch.stop()
        feed.yield(offline)
        feed.yield(wifi)
        try await Task.sleep(for: settled)
        #expect(retries.count == 2, "a stopped watch tries nothing")
    }

    // 2026-10-22: the sync line tells "back online" from "trouble reaching
    // iCloud" by the network the phone is on, and the share step a stall.
    @Test("The watch keeps the network the phone is on, for the sync line", .timeLimit(.minutes(1)))
    func currentPath() async throws {
        let (paths, feed) = AsyncStream.makeStream(of: Path.self)
        let watch = AssistantNetworkWatch(paths: paths, settle: .milliseconds(50)) {}
        #expect(watch.current == nil)
        feed.yield(wifi)
        try await Task.sleep(for: .milliseconds(200))
        #expect(watch.current == wifi)
        feed.yield(offline)
        try await Task.sleep(for: .milliseconds(200))
        #expect(watch.current == offline, "going offline is kept too, with no retry to settle")
        watch.stop()
    }

    // 2026-10-23: Low Data Mode on the network and Low Power Mode hold
    // iCloud's work back; the phone reports both, and the watch keeps them
    // for the sync line and the share step.
    @Test("Leaving Low Data Mode retries; the hold that's on is named, Low Data Mode first, never while offline")
    func holds() {
        let lowData = Path(usable: true, interface: .wifi, lowDataMode: true)
        #expect(AssistantNetworkWatch.shouldRetry(from: lowData, to: wifi), "she turned it off for this Wi-Fi")
        #expect(AssistantNetworkWatch.shouldRetry(from: lowData, to: cellular))
        #expect(!AssistantNetworkWatch.shouldRetry(from: wifi, to: lowData), "it coming on tries nothing")
        #expect(!AssistantNetworkWatch.shouldRetry(from: lowData, to: lowData))
        #expect(!AssistantNetworkWatch.shouldRetry(from: nil, to: lowData))

        #expect(AssistantNetworkWatch.hold(on: lowData, lowPowerMode: false) == .lowDataMode(.wifi))
        #expect(AssistantNetworkWatch.hold(on: lowData, lowPowerMode: true) == .lowDataMode(.wifi))
        #expect(AssistantNetworkWatch.hold(on: Path(usable: true, interface: .cellular, lowDataMode: true),
                                           lowPowerMode: false) == .lowDataMode(.cellular))
        #expect(AssistantNetworkWatch.hold(on: wifi, lowPowerMode: true) == .lowPowerMode)
        #expect(AssistantNetworkWatch.hold(on: wifi, lowPowerMode: false) == nil)
        #expect(AssistantNetworkWatch.hold(on: offline, lowPowerMode: true) == nil, "being offline comes first")
        #expect(AssistantNetworkWatch.hold(on: nil, lowPowerMode: true) == nil)
    }

    @Test("Low Power Mode going off retries at once, and the watch says when marks are clear to send",
          .timeLimit(.minutes(1)))
    func lowPowerMode() async throws {
        let (paths, feed) = AsyncStream.makeStream(of: Path.self)
        let (powers, power) = AsyncStream.makeStream(of: Bool.self)
        let retries = Retries()
        let watch = AssistantNetworkWatch(paths: paths, powerModes: powers, settle: .milliseconds(50)) {
            retries.count += 1
        }
        #expect(watch.clearToSend == nil, "before the first path")
        feed.yield(wifi)
        power.yield(false)
        power.yield(true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(watch.lowPowerMode)
        #expect(watch.hold == .lowPowerMode)
        #expect(watch.clearToSend == false)
        #expect(retries.count == 0, "Low Power Mode coming on tries nothing")

        power.yield(false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(retries.count == 1, "going off tries the waiting marks, with no link to settle")
        #expect(watch.hold == nil)
        #expect(watch.clearToSend == true)

        feed.yield(Path(usable: true, interface: .wifi, lowDataMode: true))
        try await Task.sleep(for: .milliseconds(200))
        #expect(watch.clearToSend == false)
        #expect(watch.hold == .lowDataMode(.wifi))
        #expect(retries.count == 1, "Low Data Mode coming on tries nothing")
        feed.yield(wifi)
        try await Task.sleep(for: settled)
        #expect(retries.count == 2, "leaving Low Data Mode tries the waiting marks once the link settles")
        #expect(watch.clearToSend == true)

        feed.yield(offline)
        try await Task.sleep(for: .milliseconds(100))
        #expect(watch.clearToSend == false)
        watch.stop()
    }
}

/// How many retries a watch asked for.
@MainActor
private final class Retries {
    var count = 0
}
