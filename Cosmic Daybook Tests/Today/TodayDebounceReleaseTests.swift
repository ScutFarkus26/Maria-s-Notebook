import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// State layer review 2026-11-22, safe item 6: Today's debounced reload took
/// hold of its model before the 400 ms wait, so a closed Today stayed alive
/// for the wait and then ran a full reload nobody would see.
@MainActor
@Suite("Today debounce lets a closed screen go (state layer safe 6)")
struct TodayDebounceReleaseTests {

    @Test("A Today model let go during its debounce wait is freed and reloads nothing")
    func modelLetGoDuringTheWaitIsFreed() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        weak var released: TodayViewModel?
        var pending: Task<Void, Never>?
        do {
            let viewModel = TodayViewModel(context: stack.viewContext)
            viewModel.scheduleReload()
            released = viewModel
            pending = viewModel.reloadTask
            // The debounce task starts its wait while the model is still held.
            for _ in 0..<20 { await Task.yield() }
            #expect(viewModel.reloadCount == 0)
        }
        #expect(released == nil, "the waiting task kept the closed screen's model alive")
        await pending?.value
        // Nothing is left to reload: a reload would have needed the model.
        #expect(released == nil)
    }
}
