import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - A Mac quit always gets its reply
//
// On 2026-10-18 an idle MCP-only copy of the Mac app froze mid-quit: its
// countdown task called NSApp.terminate, AppKit waited for the quit backup in
// a nested run loop, and because that loop sat inside a main-actor task no
// other main-actor task could run — not the backup, not the timeout, not the
// MCP server's stop. These tests spin a nested run loop the way AppKit's
// `.terminateLater` wait does, on the main thread of the iOS test host.

@MainActor
@Suite("Quit reply gate", .serialized)
struct QuitReplyGateTests {
    @MainActor
    private final class Box {
        var replies: [Bool] = []
        var taskRan = false
    }

    /// Spins the main run loop, as AppKit does while it waits for a reply,
    /// until `done` or the limit.
    private static func spinNestedRunLoop(seconds: Double, until done: () -> Bool = { false }) {
        let limit = Date().addingTimeInterval(seconds)
        while !done(), Date() < limit {
            _ = RunLoop.main.run(mode: .default, before: min(limit, Date().addingTimeInterval(0.02)))
        }
    }

    @Test("The deadline replies even while a quit's wait starves main-actor tasks")
    func deadlineFiresWhileStarved() {
        let box = Box()
        let gate = QuitReplyGate(timeout: .milliseconds(100)) { box.replies.append($0) }
        // What the quit backup and the old task-based timeout were: they
        // cannot run while this test's own main-actor job spins the loop.
        Task { @MainActor in box.taskRan = true }

        Self.spinNestedRunLoop(seconds: 3) { gate.hasReplied }

        #expect(box.replies == [true])
        #expect(!box.taskRan, "the nested loop should reproduce the starvation the gate exists for")
    }

    @Test("Finished work replies once, and the deadline after it sends nothing more")
    func workRepliesOnce() {
        let box = Box()
        let gate = QuitReplyGate(timeout: .milliseconds(50)) { box.replies.append($0) }

        gate.workFinished()
        gate.workFinished()
        Self.spinNestedRunLoop(seconds: 0.3)

        #expect(gate.hasReplied)
        #expect(box.replies == [false])
    }

    @Test("Work run outside the main queue can wait in a nested loop for main-actor tasks")
    func outsideMainQueueLetsTasksRun() async {
        let box = Box()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MainRunLoop.performOutsideMainQueue {
                // Where the idle quit now calls NSApp.terminate.
                Task { @MainActor in box.taskRan = true }
                Self.spinNestedRunLoop(seconds: 3) { box.taskRan }
                continuation.resume()
            }
        }
        #expect(box.taskRan)
    }
}
