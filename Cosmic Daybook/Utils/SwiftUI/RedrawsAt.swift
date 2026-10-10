// RedrawsAt.swift
// Redraws a view at a few known moments, for content that reads the clock.

import SwiftUI

/// Redraws `content` at each of `times` still ahead, and at no other moment.
///
/// For content that reads the clock itself, such as the front desk's due
/// line (due, late or neither). Use it instead of
/// `TimelineView(.explicit(times))`: once all of an explicit timeline's times
/// have passed (every day after the due time, and every past day), it redraws
/// its content every frame. That kept an idle attendance screen at 8–10% CPU
/// (2026-10-10).
///
/// The wait hangs off `content`, so `content` must draw something.
struct RedrawsAt<Content: View>: View {
    let times: [Date]
    @ViewBuilder let content: () -> Content

    /// Bumped at each time, to redraw then.
    @State private var redraws = 0

    var body: some View {
        drawn
            .task(id: times) {
                for time in Self.timesAhead(times, now: Date()) {
                    guard (try? await Task.sleep(for: .seconds(time.timeIntervalSinceNow))) != nil else { return }
                    redraws += 1
                }
            }
    }

    /// The content, drawn again whenever `redraws` moves.
    private var drawn: Content {
        _ = redraws
        return content()
    }

    /// The times still ahead of `now`: none once they have all passed, so the
    /// view then waits for nothing.
    static func timesAhead(_ times: [Date], now: Date) -> [Date] {
        times.filter { $0 > now }
    }
}
