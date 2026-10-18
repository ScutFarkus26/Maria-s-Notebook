//
//  QuitReplyGate.swift
//  Cosmic Daybook
//
//  The run-loop pieces that keep a Mac quit from freezing. Plain Foundation,
//  so the tests run them on the iOS simulator; the Mac wiring is
//  AutoBackupAppDelegate and MCPIdleQuitController.
//
//  While `applicationShouldTerminate` waits on `.terminateLater`, AppKit
//  spins a nested run loop until the reply comes. libdispatch never drains
//  the main queue re-entrantly, so when that loop is itself inside a
//  main-queue job (any main-actor Task, such as the MCP idle countdown),
//  no main-actor task runs until the reply — including the tasks meant to
//  send it. That froze an idle MCP-only copy mid-quit on 2026-10-18, still
//  holding its port. Run-loop timers are not queue jobs, so they still fire.
//

import Foundation

/// One reply per `.terminateLater`, sent by whichever comes first: the work
/// finishing, or the deadline. The deadline is a run-loop timer in the
/// common modes, so it fires inside AppKit's nested quit loop even when the
/// main queue is stuck, and the reply always comes.
@MainActor
final class QuitReplyGate {
    private var reply: ((_ timedOut: Bool) -> Void)?
    private var deadline: Timer?

    var hasReplied: Bool { reply == nil }

    init(timeout: Duration, reply: @escaping (_ timedOut: Bool) -> Void) {
        self.reply = reply
        // The timer holds the gate until it fires or `send` invalidates it,
        // so the reply comes even if the owner lets go of the gate.
        let timer = Timer(timeInterval: timeout.timeInterval, repeats: false) { _ in
            MainActor.assumeIsolated { self.send(timedOut: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        deadline = timer
    }

    func workFinished() {
        send(timedOut: false)
    }

    private func send(timedOut: Bool) {
        guard let reply else { return }
        self.reply = nil
        deadline?.invalidate()
        deadline = nil
        reply(timedOut)
    }
}

enum MainRunLoop {
    /// Runs `body` from a main run-loop timer rather than from the current
    /// main-queue job, so a nested run loop inside it (a quit's
    /// `.terminateLater` wait) still lets main-actor tasks run.
    static func performOutsideMainQueue(_ body: @escaping @MainActor @Sendable () -> Void) {
        let timer = Timer(timeInterval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { body() }
        }
        RunLoop.main.add(timer, forMode: .default)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
