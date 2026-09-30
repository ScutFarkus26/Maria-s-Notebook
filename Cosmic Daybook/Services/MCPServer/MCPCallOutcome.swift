//
//  MCPCallOutcome.swift
//  Cosmic Daybook
//
//  Lets a write tool say that one call changed nothing.
//
//  The write journal records every successful call of a tool that *can*
//  change the notebook. Some successful calls don't: a preview before
//  `confirm`, a roster edit that turns out to be the roster it already had,
//  a lesson already in the curriculum, an observation already filed. Those
//  aren't writes, and journaling them made `recent_mcp_writes` report changes
//  that never happened. The request handler binds one outcome per call; a
//  tool marks it, and the handler leaves the call out of the journal.
//

import Foundation
import Synchronization

nonisolated final class MCPCallOutcome: Sendable {
    /// The outcome of the tool call running in this task, if any.
    @TaskLocal static var current: MCPCallOutcome?

    private let nothingWritten = Mutex(false)

    /// True once the tool has said this call wrote nothing.
    var wroteNothing: Bool { nothingWritten.withLock { $0 } }

    /// Marks the running call as a preview or no-op. Outside a call (tests,
    /// in-app bridges) there is nothing to mark, and nothing happens.
    static func markNothingWritten() {
        current?.nothingWritten.withLock { $0 = true }
    }
}
