//
//  ChecklistClassCell.swift
//  Cosmic Daybook
//
//  The Class column at the end of a lesson row on the Mac and iPad: a 48-pt bar
//  (green mastered, blue in progress, orange planned) and "17/22", the children on
//  screen who have had the lesson. Under the Ready lens it reads "5 ready" with a
//  Plan button for exactly those children, or a dash when no one is ready.
//

import SwiftUI

struct ChecklistClassCell: View, Equatable {
    let summary: ChecklistRowSummary
    var lens: ChecklistLens = .allMarks
    /// The Ready lens's Plan: opens the present-a-lesson sheet for the row's ready children.
    var onPlan: (() -> Void)?

    private static let barWidth: CGFloat = 48
    private static let barHeight: CGFloat = 6

    /// The Plan closure is rebuilt with every grid render and always does the same
    /// thing for the row, so it isn't a change to redraw for.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.summary == rhs.summary && lhs.lens == rhs.lens
    }

    var body: some View {
        HStack(spacing: lens == .ready ? 6 : 8) {
            if lens == .ready {
                readyContent
            } else {
                bar
                Text("\(summary.given)/\(summary.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, lens == .ready ? 10 : 14)
        .overlay(alignment: .leading) {
            ChecklistGridMetrics.hairline.frame(width: 1)
        }
        .help(lens == .ready ? readyHelp : summary.helpText)
        .accessibilityElement(children: lens == .ready && summary.ready > 0 ? .contain : .ignore)
        .accessibilityLabel("Class")
        .accessibilityValue(
            lens == .ready ? readyHelp : summary.helpText.replacingOccurrences(of: " · ", with: ", ")
        )
    }

    @ViewBuilder
    private var readyContent: some View {
        if summary.ready > 0 {
            Text("\(summary.ready) ready")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.blue)
                .fixedSize()
            Button {
                onPlan?()
            } label: {
                Text("Plan")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 5))
            .controlSize(.mini)
            .tint(.blue)
            .fixedSize()
            .help("Present or plan this lesson for the \(summary.ready) ready")
            .accessibilityLabel("Plan for \(summary.ready) ready")
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var readyHelp: String {
        switch summary.ready {
        case 0: return "No one on screen is ready for this lesson"
        case 1: return "1 child is ready for this lesson"
        default: return "\(summary.ready) children are ready for this lesson"
        }
    }

    private var bar: some View {
        let unit = summary.total > 0 ? Self.barWidth / CGFloat(summary.total) : 0
        return HStack(spacing: 0) {
            Color.green.frame(width: unit * CGFloat(summary.mastered))
            Color.blue.frame(width: unit * CGFloat(summary.inProgress))
            Color.orange.frame(width: unit * CGFloat(summary.planned))
            Spacer(minLength: 0)
        }
        .frame(width: Self.barWidth, height: Self.barHeight)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
        .clipShape(Capsule())
    }
}
