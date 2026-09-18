// WorksAgendaView+Split.swift
// The list-over-calendar split, and the seam that separates the two halves.
//
// The guide decides how much of the week he wants in view, and that decision
// has to survive relaunching — a split that resets to a default every morning
// is a setting the app keeps forgetting.
//
// The share is stored as a fraction rather than a height so it means the same
// thing on a phone, a laptop and a resized window.
//
// The seam is drawn here, once, for both platforms and both states. It used to
// come from three different places — AppKit's `VSplitView` divider when the
// calendar was open on a Mac, the collapsed bar's own `Divider()` when it was
// folded away (which doubled the line, because the split drew one too), and a
// grabber sandwiched between two more dividers on iOS. The line between the
// workbench and the schedule changed every time the calendar was folded or a
// different list was put above it, which read as the window redrawing itself.
// One view now owns that line; only the invisible grab behaviour varies.

import SwiftUI
#if os(macOS)
import AppKit
#endif

extension WorksAgendaView {

    /// Bounds on the calendar's share of the workspace. Neither half is allowed
    /// to be squeezed down to something you cannot read or drop onto.
    static let minCalendarFraction: Double = 0.2
    static let maxCalendarFraction: Double = 0.7
    /// Floor in points, for short windows where even 20% is unusable.
    static let minCalendarHeight: CGFloat = 160
    /// The workbench's own floor, which `VSplitView` used to enforce on macOS
    /// and which now has to be honoured by the sizing itself.
    static let minWorkbenchHeight: CGFloat = 220
    /// The hairline is one point; this is the strip around it you can grab.
    static let seamThickness: CGFloat = 6

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
        let requested = max(minCalendarHeight, available * clampFraction(fraction))
        // …but the workbench keeps its own floor first. On a window too short
        // for both, the calendar gives way rather than pushing the list it is
        // fed from off the top of the screen.
        let ceiling = max(minCalendarHeight, available - minWorkbenchHeight)
        return min(requested, ceiling)
    }

    // MARK: - The split

    var workspaceSplit: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                workspaceWorkbench
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                calendarSeam(totalHeight: proxy.size.height)

                if isCalendarExpanded {
                    calendarPane
                        .frame(height: calendarHeight(in: proxy.size.height))
                } else {
                    collapsedCalendarBar
                }
            }
        }
    }

    // MARK: - The seam

    /// One line, drawn the same way whether the calendar is open or folded and
    /// whichever list is above it. Expanding only adds a drag target and a
    /// cursor — both invisible — so the seam itself never changes.
    @ViewBuilder
    private func calendarSeam(totalHeight: CGFloat) -> some View {
        if isCalendarExpanded {
            seamLine
                .contentShape(Rectangle())
                #if os(macOS)
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                #endif
                .gesture(calendarResizeGesture(totalHeight: totalHeight))
                .accessibilityElement()
                .accessibilityLabel("Resize the schedule")
                .accessibilityValue("\(Int(effectiveCalendarFraction * 100)) percent of the workspace")
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 0.05 : -0.05
                    calendarFraction = Self.clampFraction(calendarFraction + step)
                }
        } else {
            seamLine
        }
    }

    /// The hairline, centred in a strip tall enough to be grabbed. The strip is
    /// transparent, so the seam reads as a single rule rather than a gutter.
    private var seamLine: some View {
        Rectangle()
            .fill(Color.clear)
            .overlay(Divider())
            .frame(height: Self.seamThickness)
            .frame(maxWidth: .infinity)
    }

    private func calendarResizeGesture(totalHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard totalHeight > 0 else { return }
                let start = calendarResizeStartFraction ?? calendarFraction
                if calendarResizeStartFraction == nil {
                    calendarResizeStartFraction = start
                }
                // Dragging the seam up grows the calendar.
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
}
