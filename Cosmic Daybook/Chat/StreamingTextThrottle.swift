import Foundation

/// Paces a streamed answer onto the screen: the first text at once, then at
/// most one update per `interval`, each carrying the whole answer so far.
/// `flush()` delivers whatever is still waiting — call it when the stream ends
/// or fails — and cancels the scheduled update, so nothing lands after it.
///
/// Every update re-lays out and re-parses the whole message as Markdown, so
/// an update per streamed chunk cost more with every chunk; ten a second keeps
/// the text moving at a fraction of that.
@MainActor
final class StreamingTextThrottle {

    /// The throttle's rule on explicit instants, apart from any clock, so a
    /// test can replay a stream on synthetic time.
    struct Pacing {
        let interval: Duration
        private(set) var pending: String?
        private(set) var lastPublished: ContinuousClock.Instant?
        /// When the scheduled update is due, while one is.
        private(set) var dueAt: ContinuousClock.Instant?

        init(interval: Duration) {
            self.interval = interval
        }

        /// Takes the latest text: returns it when it should be shown now,
        /// otherwise keeps it for the update due at `dueAt`.
        mutating func submit(_ text: String, at now: ContinuousClock.Instant) -> String? {
            pending = text
            // An update is already scheduled; it will carry this text.
            guard dueAt == nil else { return nil }
            if let lastPublished, now < lastPublished + interval {
                dueAt = lastPublished + interval
                return nil
            }
            return takePending(at: now)
        }

        /// The scheduled update's time has come.
        mutating func fire(at now: ContinuousClock.Instant) -> String? {
            dueAt = nil
            return takePending(at: now)
        }

        /// The stream is over: whatever is waiting, now.
        mutating func flush(at now: ContinuousClock.Instant) -> String? {
            dueAt = nil
            return takePending(at: now)
        }

        private mutating func takePending(at now: ContinuousClock.Instant) -> String? {
            guard let text = pending else { return nil }
            pending = nil
            lastPublished = now
            return text
        }
    }

    private var pacing: Pacing
    private let publish: (String) -> Void
    private var scheduledUpdate: Task<Void, Never>?

    init(interval: Duration = .milliseconds(100), publish: @escaping (String) -> Void) {
        pacing = Pacing(interval: interval)
        self.publish = publish
    }

    /// Whether an update is waiting on the clock.
    var isUpdateScheduled: Bool { scheduledUpdate != nil }

    /// Hands over the answer so far.
    func submit(_ text: String) {
        if let shownNow = pacing.submit(text, at: .now) {
            publish(shownNow)
        } else if scheduledUpdate == nil, let dueAt = pacing.dueAt {
            scheduledUpdate = Task { [weak self] in
                try? await Task.sleep(until: dueAt, clock: .continuous)
                guard !Task.isCancelled else { return }
                self?.fireScheduledUpdate()
            }
        }
    }

    /// Delivers what is waiting now and cancels the scheduled update.
    func flush() {
        scheduledUpdate?.cancel()
        scheduledUpdate = nil
        if let text = pacing.flush(at: .now) {
            publish(text)
        }
    }

    private func fireScheduledUpdate() {
        scheduledUpdate = nil
        if let text = pacing.fire(at: .now) {
            publish(text)
        }
    }
}
