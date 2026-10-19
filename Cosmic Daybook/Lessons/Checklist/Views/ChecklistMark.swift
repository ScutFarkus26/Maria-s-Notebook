//
//  ChecklistMark.swift
//  Cosmic Daybook
//
//  The Class Grid's one mark, in all four views (it replaced the Three-Year View's
//  glyph): a grey dot (not yet), a grey ring (ready), a dashed orange ring
//  (planned), a blue ring filling a quarter, half and three quarters (presented,
//  practicing, reviewing), then solid green with a check (mastered, only for a
//  mastery mark). A small amber dot on top means look before you act: a check-in
//  is due, or a Ready cell is "Ready, check first". Three Years and Recall draw
//  the latest recall check as an outline outside the mark: solid green (still has
//  it), dashed orange (shaky), dotted red (forgotten). Plain shapes in system
//  colors, so a grid of them is cheap and dark mode works.
//

import SwiftUI

struct ChecklistMark: View, Equatable {
    let status: ChecklistDisplayStatus
    var needsCheckIn: Bool = false
    /// A Ready cell that is "Ready, check first": the amber dot on its grey ring.
    var checkFirst: Bool = false
    /// The latest recall check, drawn as an outline outside the mark.
    var recall: RecallOutcome?
    var size: CGFloat = 15
    /// The Ready lens: a Ready ring turns blue and heavier, filled with the background
    /// so it reads on the lens's tinted tile.
    var emphasizesReady: Bool = false

    private var lineWidth: CGFloat { max(1.25, size * 0.1) }

    /// The amber dot: a check-in is due, or the cell is Ready, check first.
    private var showsAmberDot: Bool {
        needsCheckIn || (checkFirst && status == .ready)
    }

    var body: some View {
        mark
            .frame(width: size, height: size)
            .overlay {
                if let recall { recallRing(recall) }
            }
            .overlay(alignment: .topTrailing) {
                if showsAmberDot { checkInDot }
            }
            .animation(.snappy(duration: 0.25), value: status)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        switch status {
        case .notReady:
            Circle()
                .fill(.tertiary)
                .frame(width: size * 0.32, height: size * 0.32)
        case .ready where emphasizesReady:
            // Under the Ready lens: blue for Ready, amber for Ready, check first.
            Circle()
                .fill(ChecklistGridMetrics.surface)
                .overlay(Circle().strokeBorder(
                    checkFirst ? ChecklistGridMetrics.checkFirstInk : Color.blue, lineWidth: lineWidth * 1.4
                ))
        case .ready:
            Circle()
                .strokeBorder(.secondary, lineWidth: lineWidth)
        case .planned:
            Circle()
                .strokeBorder(
                    Color.orange,
                    style: StrokeStyle(lineWidth: lineWidth, dash: [size * 0.17, size * 0.12])
                )
        case .presented, .practicing, .reviewing:
            // One branch for the three blue rungs, so a step up animates the fill.
            ZStack {
                ChecklistPie(fraction: Self.fraction(for: status))
                    .fill(Color.blue)
                Circle()
                    .strokeBorder(Color.blue, lineWidth: lineWidth)
            }
        case .mastered:
            ZStack {
                Circle()
                    .fill(Color.green)
                // White reads on the green fill in light and dark mode alike.
                ChecklistCheckShape()
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round, lineJoin: .round)
                    )
            }
        }
    }

    /// The latest recall check, an outline a little outside the mark. Mastery itself
    /// never changes; the ring only says how the last check went.
    private func recallRing(_ recall: RecallOutcome) -> some View {
        let width = max(1.25, size * 0.12)
        let style: StrokeStyle = switch recall {
        case .retained: StrokeStyle(lineWidth: width)
        case .shaky: StrokeStyle(lineWidth: width, dash: [size * 0.22, size * 0.14])
        case .forgotten: StrokeStyle(lineWidth: width, lineCap: .round, dash: [0.1, size * 0.2])
        }
        return Circle()
            .stroke(Self.recallColor(recall), style: style)
            .frame(width: size + size * 0.5, height: size + size * 0.5)
            .allowsHitTesting(false)
    }

    static func recallColor(_ recall: RecallOutcome) -> Color {
        switch recall {
        case .retained: .green
        case .shaky: .orange
        case .forgotten: .red
        }
    }

    /// What the mark says, for VoiceOver and hover text: "Mastered, recall shaky".
    static func label(status: ChecklistDisplayStatus, recall: RecallOutcome?) -> String {
        let base = status == .notReady ? "Not yet" : status.label
        guard let recall else { return base }
        switch recall {
        case .retained: return "\(base), still has it"
        case .shaky: return "\(base), recall shaky"
        case .forgotten: return "\(base), forgotten"
        }
    }

    /// The amber "needs a check-in" dot, ringed in the background color so it reads on any mark.
    private var checkInDot: some View {
        let diameter = max(5, size * 0.4)
        return Circle()
            .fill(Color.orange)
            .overlay(Circle().stroke(Color.windowBackgroundColor(), lineWidth: 1.25))
            .frame(width: diameter, height: diameter)
            .offset(x: diameter * 0.35, y: -diameter * 0.35)
    }

    /// How much of the ring the blue rungs fill.
    static func fraction(for status: ChecklistDisplayStatus) -> Double {
        switch status {
        case .presented: return 0.25
        case .practicing: return 0.5
        case .reviewing: return 0.75
        case .mastered: return 1
        case .notReady, .ready, .planned: return 0
        }
    }
}

/// The amber dot alone, for the legend's "Needs a check-in" entry.
struct ChecklistCheckInDot: View {
    var size: CGFloat = 15

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: size * 0.45, height: size * 0.45)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A pie wedge from twelve o'clock, clockwise, `fraction` of the way round.
/// Animatable, so a mark that steps up a rung fills rather than jumps.
nonisolated struct ChecklistPie: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        guard fraction < 1 else {
            path.addEllipse(in: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
            ))
            return path
        }
        path.move(to: center)
        // y grows downward here, so `clockwise: false` draws clockwise on screen.
        path.addArc(
            center: center, radius: radius,
            startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// The mastered mark's check, drawn in the unit square of its frame.
nonisolated struct ChecklistCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.67))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.36))
        return path
    }
}

private struct ChecklistMarkPreview: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(ChecklistDisplayStatus.allCases, id: \.self) { status in
                ChecklistMark(status: status)
            }
            ChecklistMark(status: .practicing, needsCheckIn: true)
            ChecklistMark(status: .ready, emphasizesReady: true)
            ChecklistMark(status: .ready, checkFirst: true)
            ChecklistMark(status: .mastered, recall: .retained)
            ChecklistMark(status: .mastered, recall: .shaky)
            ChecklistMark(status: .reviewing, recall: .forgotten)
        }
        .padding()
    }
}

#Preview {
    ChecklistMarkPreview()
}
