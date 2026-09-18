// CurriculumCellGlyph.swift
// The one drawing both Three-Year View screens share: a dot that fills as a
// lesson climbs the ladder, ringed by the latest recall outcome.
//
//   empty        not yet presented
//   outline dot  presented
//   half dot     chosen
//   filled dot   repeated
//   dot + ring   mastered
//   ring colour  retained / shaky / forgotten

import SwiftUI

struct CurriculumCellGlyph: View {
    let state: CurriculumCellState
    var recall: RecallOutcome?
    var tint: Color = .accentColor
    var size: CGFloat = 12
    /// Draw a faint placeholder for "not presented" so the grid keeps its rhythm.
    var showsEmpty = true

    var body: some View {
        ZStack {
            if let recall {
                Circle()
                    .stroke(Self.color(for: recall), lineWidth: max(1.5, size / 7))
                    .frame(width: size + 6, height: size + 6)
            }
            switch state {
            case .notPresented:
                if showsEmpty {
                    Circle()
                        .fill(Color.secondary.opacity(UIConstants.OpacityConstants.light))
                        .frame(width: size * 0.4, height: size * 0.4)
                }
            case .presented:
                Circle()
                    .stroke(tint, lineWidth: max(1.5, size / 7))
                    .frame(width: size, height: size)
            case .chosen:
                Circle()
                    .stroke(tint, lineWidth: max(1.5, size / 7))
                    .frame(width: size, height: size)
                HalfCircle()
                    .fill(tint)
                    .frame(width: size, height: size)
            case .repeated:
                Circle()
                    .fill(tint)
                    .frame(width: size, height: size)
            case .mastered:
                Circle()
                    .stroke(tint, lineWidth: max(1.5, size / 7))
                    .frame(width: size + 6, height: size + 6)
                    .opacity(recall == nil ? 1 : 0)
                Circle()
                    .fill(tint)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size + 8, height: size + 8)
        .accessibilityHidden(true)
    }

    static func color(for recall: RecallOutcome) -> Color {
        switch recall {
        case .retained: .green
        case .shaky: .orange
        case .forgotten: .red
        }
    }

    static func label(state: CurriculumCellState, recall: RecallOutcome?) -> String {
        guard let recall else { return state.label }
        return "\(state.label), recall \(recall.rawValue)"
    }
}

/// The left half of a circle — "chosen": presented, then picked up.
nonisolated private struct HalfCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center, radius: rect.width / 2,
            startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// The legend both screens show under their toolbars.
struct CurriculumLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(CurriculumCellState.allCases, id: \.rawValue) { state in
                HStack(spacing: 4) {
                    CurriculumCellGlyph(state: state, tint: .secondary, size: 9)
                    Text(state.label)
                }
            }
            HStack(spacing: 4) {
                CurriculumCellGlyph(state: .mastered, recall: .shaky, tint: .secondary, size: 9)
                Text("Recall ring")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Legend: empty not presented, outline presented, half dot chosen, filled repeated, "
                + "ringed mastered; ring colour is the latest recall outcome"
        )
    }
}
