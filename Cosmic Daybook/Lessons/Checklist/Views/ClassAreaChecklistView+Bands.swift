// ClassAreaChecklistView+Bands.swift
// The grid's two grouping rows: the sequence band ("Preliminary · 10 lessons"), which
// folds its lessons away, and the light section caption ("Stamp Game") inside it.
// Neutral greys, never the accent: blue is the ladder's "started".

import SwiftUI

extension ClassAreaChecklistView {

    /// A band's fill: the grid's surface with a faint grey over it. Opaque, so the
    /// sticky half reads cleanly where it slides over the rest of the row.
    private var bandFill: some View {
        ZStack {
            gridSurface
            ChecklistGridMetrics.bandFill
        }
    }

    /// Top-level grouping — "Preliminary", "Early Work" — with a chevron that folds
    /// its lessons away (remembered per area) and how many lessons it holds. A heavier
    /// rule above it marks the seam however far the grid is scrolled. An empty name is
    /// the band for lessons not yet filed under a sequence, called "Other" here and on
    /// the scope-and-sequence map alike.
    func sequenceRow(
        name: String, lessonCount: Int, isCollapsed: Bool, studentCount: Int, metrics: ChecklistGridMetrics
    ) -> some View {
        let height = metrics.sequenceBandHeight
        let title = name.isEmpty ? "Other" : name
        let count = "\(lessonCount) lesson\(lessonCount == 1 ? "" : "s")"
        // While a search narrows the rows every band is open, so the fold does nothing.
        let canFold = !viewModel.isSearchingLessons
        return HStack(spacing: 0) {
            StickyLeftItem(width: metrics.lessonColumnWidth, height: height) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.toggleCollapsed(name)
                    }
                } label: {
                    sequenceLabel(
                        title: title, count: count, isCollapsed: isCollapsed, canFold: canFold, metrics: metrics
                    )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(canFold)
                .help(canFold ? (isCollapsed ? "Show \(title)'s lessons" : "Hide \(title)'s lessons") : title)
                .accessibilityLabel("\(title), \(count)")
                .accessibilityValue(canFold ? (isCollapsed ? "Collapsed" : "Expanded") : "")
                .accessibilityAddTraits(.isHeader)
            }

            bandFill
                .frame(width: metrics.rowWidth(studentCount: studentCount) - metrics.lessonColumnWidth, height: height)
        }
        .overlay(alignment: .top) {
            ChecklistGridMetrics.blockRule
                .frame(height: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            ChecklistGridMetrics.hairline
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
    }

    /// Chevron, name, lesson count.
    private func sequenceLabel(
        title: String, count: String, isCollapsed: Bool, canFold: Bool, metrics: ChecklistGridMetrics
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .opacity(canFold ? 1 : 0)
            Text(title)
                .font(.system(.subheadline).weight(.bold))
                .lineLimit(1)
            Text(count)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(-1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(width: metrics.lessonColumnWidth, height: metrics.sequenceBandHeight, alignment: .leading)
        .background(bandFill)
        .contentShape(Rectangle())
    }

    /// Second-level grouping inside a sequence — "Chains", "Stamp Game": a light
    /// caption sitting on the rows below it, no fill.
    func sectionRow(name: String, studentCount: Int, metrics: ChecklistGridMetrics) -> some View {
        let height = metrics.sectionCaptionHeight
        return HStack(spacing: 0) {
            StickyLeftItem(width: metrics.lessonColumnWidth, height: height) {
                Text(name.isEmpty ? "Other" : name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, metrics.isRegular ? 32 : 24)
                    .padding(.trailing, 8)
                    .padding(.bottom, 4)
                    .frame(width: metrics.lessonColumnWidth, height: height, alignment: .bottomLeading)
                    .background(gridSurface)
                    .accessibilityAddTraits(.isHeader)
            }

            gridSurface
                .frame(width: metrics.rowWidth(studentCount: studentCount) - metrics.lessonColumnWidth, height: height)
        }
    }
}
