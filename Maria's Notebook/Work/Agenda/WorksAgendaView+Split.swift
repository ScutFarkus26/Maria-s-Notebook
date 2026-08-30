// WorksAgendaView+Split.swift
// The list-over-calendar split, and the divider that sizes it.
//
// The guide decides how much of the week he wants in view, and that decision
// has to survive relaunching — a split that resets to a default every morning
// is a setting the app keeps forgetting.
//
// The share is stored as a fraction rather than a height so it means the same
// thing on a phone, a laptop and a resized window. Both platforms write the
// same key; only the gesture differs, because AppKit already gives a Mac window
// a real split divider and iOS does not.

import SwiftUI

extension WorksAgendaView {

    /// Bounds on the calendar's share of the workspace. Neither half is allowed
    /// to be squeezed down to something you cannot read or drop onto.
    static let minCalendarFraction: Double = 0.2
    static let maxCalendarFraction: Double = 0.7
    /// Floor in points, for short windows where even 20% is unusable.
    static let minCalendarHeight: CGFloat = 160

    /// The share in effect right now — the live drag if one is in progress,
    /// otherwise the stored setting.
    var effectiveCalendarFraction: Double {
        Self.clampFraction(liveCalendarFraction ?? calendarFraction)
    }

    static func clampFraction(_ fraction: Double) -> Double {
        min(max(fraction, minCalendarFraction), maxCalendarFraction)
    }

    func calendarHeight(in available: CGFloat) -> CGFloat {
        Self.calendarHeight(fraction: effectiveCalendarFraction, in: available)
    }

    /// Pure so the bounds can be tested without standing up the view.
    static func calendarHeight(fraction: Double, in available: CGFloat) -> CGFloat {
        // The points floor wins on short windows, where even the minimum share
        // would leave a calendar too shallow to drop onto.
        max(minCalendarHeight, available * clampFraction(fraction))
    }

    /// Writes the new share, coalescing the flurry of intermediate values a
    /// drag produces into one stored value once it settles.
    func persistCalendarFraction(_ fraction: Double) {
        let clamped = Self.clampFraction(fraction)
        // A sub-half-percent change is noise from layout rounding, not a
        // decision worth writing to disk.
        guard abs(clamped - calendarFraction) > 0.005 else { return }
        calendarResizeTask?.cancel()
        calendarResizeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            calendarFraction = clamped
        }
    }

    // MARK: - The split

    @ViewBuilder
    var workspaceSplit: some View {
        #if os(macOS)
        GeometryReader { proxy in
            VSplitView {
                workspaceWorkbench
                    .frame(minHeight: 220)
                if isCalendarExpanded {
                    calendarPane
                        .frame(
                            minHeight: Self.minCalendarHeight,
                            idealHeight: restoredCalendarHeight(in: proxy.size.height)
                        )
                        .background(calendarHeightReporter(totalHeight: proxy.size.height))
                } else {
                    collapsedCalendarBar
                }
            }
        }
        #else
        GeometryReader { proxy in
            VStack(spacing: 0) {
                workspaceWorkbench
                    .frame(maxHeight: .infinity)
                if isCalendarExpanded {
                    calendarResizeHandle(totalHeight: proxy.size.height)
                    calendarPane
                        .frame(height: calendarHeight(in: proxy.size.height))
                } else {
                    collapsedCalendarBar
                }
            }
        }
        #endif
    }

    // MARK: - macOS: let AppKit drive, and record where it landed

    #if os(macOS)
    /// The height to open at. Read from a snapshot taken once per appearance,
    /// not from the live setting — feeding the stored value back into the split
    /// while the split is reporting its height would fight the guide's drag.
    private func restoredCalendarHeight(in available: CGFloat) -> CGFloat {
        let fraction = Self.clampFraction(restoredCalendarFraction ?? calendarFraction)
        return max(Self.minCalendarHeight, available * fraction)
    }

    /// `VSplitView` has no binding for its divider, so the pane's own height is
    /// the only way to learn where the guide put it.
    private func calendarHeightReporter(totalHeight: CGFloat) -> some View {
        GeometryReader { inner in
            Color.clear
                .onChange(of: inner.size.height, initial: false) { _, height in
                    guard totalHeight > 0 else { return }
                    persistCalendarFraction(Double(height / totalHeight))
                }
        }
    }
    #endif

    // MARK: - iOS: draw the divider and drag it ourselves

    #if !os(macOS)
    private func calendarResizeHandle(totalHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider()
            Capsule()
                .fill(Color.secondary.opacity(UIConstants.OpacityConstants.moderate))
                .frame(width: 36, height: 4)
                .padding(.vertical, 5)
            Divider()
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        // The grabber is deliberately small; the touch target is not.
        .contentShape(Rectangle())
        .gesture(calendarResizeGesture(totalHeight: totalHeight))
        .accessibilityElement()
        .accessibilityLabel("Resize the schedule")
        .accessibilityValue("\(Int(effectiveCalendarFraction * 100)) percent of the screen")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            calendarFraction = Self.clampFraction(calendarFraction + step)
        }
    }

    private func calendarResizeGesture(totalHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard totalHeight > 0 else { return }
                let start = calendarResizeStartFraction ?? calendarFraction
                if calendarResizeStartFraction == nil {
                    calendarResizeStartFraction = start
                }
                // Dragging the divider up grows the calendar.
                liveCalendarFraction = Self.clampFraction(
                    start + Double(-value.translation.height / totalHeight)
                )
            }
            .onEnded { _ in
                // Written once, at rest — not on every frame of the drag.
                if let settled = liveCalendarFraction {
                    calendarFraction = settled
                }
                calendarResizeStartFraction = nil
                liveCalendarFraction = nil
            }
    }
    #endif
}
