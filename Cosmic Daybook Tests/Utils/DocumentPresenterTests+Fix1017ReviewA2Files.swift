#if os(iOS)
import Foundation
import Testing
@testable import CosmicDaybook

// Review of the 2026-10-17 bug-hunt fixes (a2), #8. Opening a file waits for
// it to come down from iCloud (up to a minute) before showing it. Two taps
// stacked two sheets, and a sheet could appear after she had left the screen.
// Now one file is opened at a time, and a wait whose tap was cancelled shows
// nothing.

@Suite("Opening a file on iPhone and iPad (Fix1017ReviewA2Files)")
@MainActor
struct DocumentPresenterReviewTests {

    private static func missingFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fix1017a2-\(UUID().uuidString).pdf")
    }

    /// Lets the first open reach its wait for the file.
    private func waitUntilBusy() async {
        for _ in 0..<200 where !DocumentPresenter.isBusy {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("A second tap while a file is on its way does nothing, and a later tap works again")
    func secondTapIsIgnored() async {
        let file = Self.missingFile()
        let (arrival, arrived) = AsyncStream<Void>.makeStream()
        let first = Task {
            await DocumentPresenter.open(file, as: .preview) { url in
                for await _ in arrival {}
                return url
            }
        }
        await waitUntilBusy()
        #expect(DocumentPresenter.isBusy)

        let second = await DocumentPresenter.open(file, as: .preview) { $0 }
        #expect(second == .busy)
        #expect(second.message == nil, "a second tap says nothing")

        arrived.finish()
        #expect(await first.value == .fileMissing)
        #expect(!DocumentPresenter.isBusy)
        #expect(await DocumentPresenter.open(file, as: .preview) { $0 } == .fileMissing)
        #expect(!DocumentPresenter.isBusy)
    }

    @Test("When the tap is cancelled during the wait (she left the screen), nothing is shown")
    func cancelledWaitShowsNothing() async {
        let file = Self.missingFile()
        let first = Task {
            await DocumentPresenter.open(file, as: .share) { url in
                try? await Task.sleep(for: .seconds(10))
                return url
            }
        }
        await waitUntilBusy()
        first.cancel()
        let outcome = await first.value
        #expect(outcome == .cancelled)
        #expect(outcome.message == nil)
        #expect(!DocumentPresenter.isBusy)
    }
}
#endif
