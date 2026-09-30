import Testing
@testable import CosmicDaybook

/// Pins the sky icon's weather: each sync state gets its own symbol and a spoken label.
@Suite("Sync sky icon")
@MainActor
struct SyncSkyIconTests {

    private let states: [CloudKitHealthCheck.SyncHealth] = [
        .healthy, .syncing, .warning, .error("x"), .offline, .unknown
    ]

    @Test("Sun when healthy, rain on an error, the moon when offline")
    func weatherMatchesHealth() {
        #expect(SyncSkyIcon.symbolName(for: .healthy) == "sun.max.fill")
        #expect(SyncSkyIcon.symbolName(for: .syncing) == "cloud.fill")
        #expect(SyncSkyIcon.symbolName(for: .warning) == "cloud.sun.fill")
        #expect(SyncSkyIcon.symbolName(for: .error("Timed out")) == "cloud.rain.fill")
        #expect(SyncSkyIcon.symbolName(for: .offline) == "moon.zzz.fill")
        #expect(SyncSkyIcon.symbolName(for: .unknown) == "cloud")
    }

    @Test("Every state has its own symbol and VoiceOver label")
    func statesAreDistinct() {
        let symbols = states.map(SyncSkyIcon.symbolName(for:))
        let labels = states.map(SyncSkyIcon.accessibilityLabel(for:))
        #expect(Set(symbols).count == states.count)
        #expect(Set(labels).count == states.count)
        #expect(SyncSkyIcon.accessibilityLabel(for: .healthy) == "Sync healthy")
    }
}
