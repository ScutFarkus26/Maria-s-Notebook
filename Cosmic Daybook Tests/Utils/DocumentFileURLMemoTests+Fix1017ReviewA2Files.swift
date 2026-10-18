import Foundation
import Observation
import Testing
@testable import CosmicDaybook

// Review of the 2026-10-17 bug-hunt fixes (a2), #10. A file that wasn't found
// was looked up again on every redraw, and one arriving from iCloud showed up
// only if something unrelated redrew the screen. The memo now remembers "not
// found" between rechecks, looks again every few seconds for a bounded time,
// and tells the screen to redraw when it does.

@Suite("Document file memo rechecks (Fix1017ReviewA2Files)")
@MainActor
struct DocumentFileURLMemoReviewTests {

    @MainActor
    private final class Download {
        static let report = URL(fileURLWithPath: "/Student Files/Ada/Report.pdf")
        var arrived = false
        var lookups = 0

        func resolve(_ bookmark: Data?, _ path: String) -> URL? {
            lookups += 1
            return arrived ? Self.report : nil
        }
    }

    /// Waits until `memo` tells an observer it changed, or `limit` passes.
    private func nextChange(of memo: DocumentFileURLMemo, read: () -> Void, limit: Duration) async -> Bool {
        let changed = AsyncStream<Void>.makeStream()
        withObservationTracking(read) { changed.continuation.yield() }
        let timeout = Task {
            try? await Task.sleep(for: limit)
            changed.continuation.finish()
        }
        defer { timeout.cancel() }
        for await _ in changed.stream { return true }
        return false
    }

    @Test("Redraws while the file is missing don't look it up again until the recheck")
    func missingFileIsNotLookedUpOnEveryRedraw() {
        let memo = DocumentFileURLMemo(recheckInterval: .seconds(60), recheckLimit: .seconds(120))
        let download = Download()
        for _ in 0..<10 {
            #expect(memo.url(bookmark: Data([1]), relativePath: "Ada/Report", resolve: download.resolve) == nil)
        }
        #expect(download.lookups == 1)
        #expect(memo.resolutionCount == 1)
    }

    @Test("A file that arrives is found by the recheck, which redraws the screen")
    func recheckFindsAnArrivingFile() async {
        let memo = DocumentFileURLMemo(recheckInterval: .milliseconds(30), recheckLimit: .seconds(10))
        let download = Download()
        let read = { _ = memo.url(bookmark: Data([1]), relativePath: "Ada/Report", resolve: download.resolve) }
        read()
        #expect(download.lookups == 1)

        download.arrived = true
        // Nothing else redraws the screen: the memo itself has to.
        #expect(await nextChange(of: memo, read: read, limit: .seconds(5)), "the screen is told to redraw")
        #expect(memo.url(bookmark: Data([1]), relativePath: "Ada/Report", resolve: download.resolve)
            == Download.report)
        let lookups = download.lookups

        // Found, it is remembered and the rechecks stop.
        try? await Task.sleep(for: .milliseconds(150))
        for _ in 0..<10 {
            #expect(memo.url(bookmark: Data([1]), relativePath: "Ada/Report", resolve: download.resolve)
                == Download.report)
        }
        #expect(download.lookups == lookups)
    }

    @Test("Rechecking stops after the limit")
    func recheckingStopsAfterTheLimit() async {
        let memo = DocumentFileURLMemo(recheckInterval: .milliseconds(20), recheckLimit: .milliseconds(150))
        let download = Download()
        let read = { _ = memo.url(bookmark: Data([1]), relativePath: "Gone", resolve: download.resolve) }
        read()

        // Within the limit, the memo keeps prompting a redraw.
        #expect(await nextChange(of: memo, read: read, limit: .seconds(5)))
        read()

        // Past it, no more prompts and no more lookups.
        try? await Task.sleep(for: .milliseconds(400))
        read()
        let lookups = download.lookups
        #expect(await nextChange(of: memo, read: read, limit: .milliseconds(300)) == false)
        for _ in 0..<10 { read() }
        #expect(download.lookups == lookups)
    }

    @Test("A new bookmark or path is looked up at once, missing or not")
    func newValueIsLookedUpAtOnce() {
        let memo = DocumentFileURLMemo(recheckInterval: .seconds(60), recheckLimit: .seconds(120))
        let download = Download()
        _ = memo.url(bookmark: Data([1]), relativePath: "Ada/Report", resolve: download.resolve)
        _ = memo.url(bookmark: Data([2]), relativePath: "Ada/Report", resolve: download.resolve)
        _ = memo.url(bookmark: Data([2]), relativePath: "Ada/Other", resolve: download.resolve)
        #expect(download.lookups == 3)
    }
}
