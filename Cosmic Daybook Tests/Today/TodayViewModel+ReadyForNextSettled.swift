@testable import CosmicDaybook

extension TodayViewModel {
    /// Waits until no rebuild of the ready queue is reading the record off
    /// the main thread, so `readyForNext` holds the newest rebuild's queue.
    /// A rebuild started while waiting is waited for too.
    func readyForNextSettled() async {
        while let task = readyForNextTask {
            await task.value
            // A dropped rebuild leaves the newer one in its place; one that
            // published has cleared it. Anything else would never change.
            guard readyForNextTask != task else { return }
        }
    }
}
