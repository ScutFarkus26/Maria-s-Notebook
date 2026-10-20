import Foundation
import CoreData
import OSLog

// After each round of a pass: whether it goes again at once, how long the
// backlog rests, and what a mirroring stop means for the stack.

extension AssistantShareAttacher {
    private static let roundsLogger = Logger.app(category: "shareAttach")

    /// A round that left marks after a retry was asked for during it goes
    /// again now, with the backlog. The try the retry cut short isn't
    /// counted or rested on: counting it doubled the next rest whenever the
    /// second go failed too. Not when CloudKit asked to wait, or the round
    /// can't simply go again (mirroring stopped, the stack rebuilt).
    func goesAgainAtOnce(
        _ result: CDAttendanceStore.ShareAttachResult,
        on container: NSPersistentCloudKitContainer,
        someWentIn: Bool
    ) -> Bool {
        guard !result.left.isEmpty, !result.mirroringStopped, result.retryAfter == nil,
              lastContainer === container else { return false }
        isOffline = result.noConnection && !someWentIn
        backlogWaitsUntil = notBefore
        runAgain = true
        return true
    }

    /// The rest, retry and next round after a round on `container`. Returns
    /// false when nothing more may run on it.
    func afterRound(
        _ result: CDAttendanceStore.ShareAttachResult,
        on container: NSPersistentCloudKitContainer,
        backlogDue: Bool,
        wasEarly: Bool,
        someWentIn: Bool
    ) -> Bool {
        if result.mirroringStopped { return mirroringStopped(on: container) }
        if result.left.isEmpty {
            failuresInARow = 0
            networkFailuresInARow = 0
            if backlogDue {
                backlogWaitsUntil = notBefore
            } else if !pending.isEmpty, !earlyTryFailed, now() >= notBefore {
                // CloudKit took every mark it was given, so it's working:
                // go round now for the marks it held back.
                backlogWaitsUntil = .distantPast
                triedEarly = true
                runAgain = true
            }
        } else if lastContainer !== container {
            // The stack was rebuilt under this round, so the refusals
            // were the closed stack's: try them on the new one now.
            runAgain = true
        } else {
            if wasEarly { earlyTryFailed = true }
            var rest: TimeInterval
            // Offline only when nothing reached iCloud: a refusal did (bug
            // hunt 2026-10-16 #2), and so did a mark that went in before
            // the connection dropped.
            isOffline = result.noConnection && !someWentIn
            if result.noConnection {
                networkFailuresInARow += 1
                rest = Self.rest(afterFailures: networkFailuresInARow, noConnection: true)
            } else {
                failuresInARow += 1
                rest = Self.rest(afterFailures: failuresInARow)
            }
            if let wait = result.retryAfter {
                notBefore = now().addingTimeInterval(wait)
                rest = max(rest, wait)
            }
            // Never before CloudKit's own wait ends. A fresh mark refused
            // offline during a 300 s wait set a 30 s retry in place of the
            // wait's, and at 30 s the backlog wasn't due, so nothing set
            // another: it waited for the next tap (2026-10-20 review b,
            // item 6).
            rest = max(rest, notBefore.timeIntervalSince(now()))
            backlogWaitsUntil = now().addingTimeInterval(rest)
            scheduleRetry(after: rest)
            Self.roundsLogger.notice(
                "\(result.left.count, privacy: .public) mark(s) wait \(Int(rest), privacy: .public) s for the next try"
            )
        }
        return true
    }

    /// No pass runs on `container` again; the bootstrapper hears of it.
    /// Returns whether a rebuilt stack arrived meanwhile, which can try the
    /// marks now.
    func mirroringStopped(on container: NSPersistentCloudKitContainer) -> Bool {
        stoppedContainer = container
        // The line says so in its own words (`sendingStopped`), not "offline".
        isOffline = false
        retryTask?.cancel()
        Self.roundsLogger.error(
            "CloudKit mirroring stopped; \(self.pending.count, privacy: .public) mark(s) wait for a new stack"
        )
        if let onMirroringStopped { onMirroringStopped(container) } else { unheardStop = container }
        guard lastContainer !== container else { return false }
        runAgain = true
        return true
    }
}
