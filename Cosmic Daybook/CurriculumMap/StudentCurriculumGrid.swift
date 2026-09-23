// StudentCurriculumGrid.swift
// The grid itself: a sticky label column and one glyph per time bucket. Rows
// are precomputed by StudentCurriculumMapModel, so drawing is a matter of
// laying out what it already decided.

import SwiftUI

struct StudentCurriculumGrid: View {
    let rows: [CurriculumRow]
    let timeline: CurriculumTimeline
    let settings: CurriculumMapSettings
    let onToggleArea: (String) -> Void
    let onOpen: (CurriculumRow, CurriculumColumn?) -> Void
    let onSetUntouched: (String, Int?) -> Void

    private let labelWidth: CGFloat = 250
    private var columnWidth: CGFloat {
        switch timeline.zoom {
        case .years: 150
        case .terms: 78
        case .months: 46
        }
    }
    private var gridWidth: CGFloat { labelWidth + CGFloat(timeline.columns.count) * columnWidth }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { row in
                        gridRow(row)
                    }
                } header: {
                    header
                }
            }
            .frame(minWidth: gridWidth, alignment: .leading)
        }
        .coordinateSpace(name: "gridSpace")
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                StickyLeftItem(width: labelWidth, height: 26) {
                    ZStack {
                        Color.clear.backgroundPlatform()
                        Text("Curriculum \\ Years")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: labelWidth, height: 26)
                    .borderSeparated()
                }
                ForEach(timeline.columnsByYear, id: \.year) { band in
                    Text(CurriculumTimeline.yearBadge(band.year))
                        .font(.caption.weight(.semibold))
                        .frame(width: CGFloat(band.columns.count) * columnWidth, height: 26)
                        .background(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                        .borderSeparated()
                }
            }
            if timeline.zoom != .years {
                HStack(spacing: 0) {
                    StickyLeftItem(width: labelWidth, height: 22) {
                        Color.clear.backgroundPlatform()
                            .frame(width: labelWidth, height: 22)
                            .borderSeparated()
                    }
                    ForEach(timeline.columns) { column in
                        Text(column.label)
                            .font(.caption2)
                            .foregroundStyle(column.isFuture ? .tertiary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: columnWidth, height: 22)
                            .backgroundPlatform()
                            .borderSeparated()
                            .help(column.detail)
                    }
                }
            }
        }
        .zIndex(100)
    }

    // MARK: - Rows

    private func rowHeight(_ row: CurriculumRow) -> CGFloat {
        switch row.kind {
        case .greatLessonsHeader, .area: 36
        case .greatLesson, .sequence: 30
        case .lesson: 28
        }
    }

    private func gridRow(_ row: CurriculumRow) -> some View {
        let height = rowHeight(row)
        return HStack(spacing: 0) {
            StickyLeftItem(width: labelWidth, height: height) {
                labelCell(row, height: height)
            }
            ForEach(timeline.columns) { column in
                let glyph = row.glyphs[column.index]
                Button {
                    onOpen(row, column)
                } label: {
                    ZStack {
                        rowBand(row)
                        if column.isFuture {
                            Color.secondary.opacity(UIConstants.OpacityConstants.hint)
                        }
                        if let glyph {
                            CurriculumCellGlyph(state: glyph.state, recall: glyph.recall, tint: row.tint, size: 11)
                        }
                    }
                    .frame(width: columnWidth, height: height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(glyph == nil)
                .borderSeparated()
                .accessibilityLabel("\(row.title), \(column.label)")
                .accessibilityValue(
                    glyph.map { CurriculumCellGlyph.label(state: $0.state, recall: $0.recall) } ?? "nothing recorded"
                )
            }
        }
    }

    @ViewBuilder
    private func rowBand(_ row: CurriculumRow) -> some View {
        switch row.kind {
        case .greatLessonsHeader, .area:
            row.tint.opacity(UIConstants.OpacityConstants.veryFaint)
        case .greatLesson, .sequence:
            Color.secondary.opacity(UIConstants.OpacityConstants.whisper)
        case .lesson:
            Color.clear
        }
    }

    private func labelCell(_ row: CurriculumRow, height: CGFloat) -> some View {
        HStack(spacing: 6) {
            if row.isExpandable {
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.hairline)
                .fill(row.tint)
                .frame(width: 3, height: height - 12)
                .opacity(row.depth == 0 ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(titleFont(row))
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailingIndicators(row)
        }
        .padding(.leading, 8 + CGFloat(row.depth) * 14)
        .padding(.trailing, 6)
        .frame(width: labelWidth, height: height, alignment: .leading)
        .background(rowBand(row))
        .backgroundPlatform()
        .borderSeparated()
        .contentShape(Rectangle())
        .onTapGesture {
            if case .area(let area) = row.kind {
                onToggleArea(area)
            } else if !row.lessonIDs.isEmpty {
                onOpen(row, nil)
            }
        }
        .contextMenu { contextMenu(row) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// The untouched flag and the row's overall state, at the right edge of the label.
    @ViewBuilder
    private func trailingIndicators(_ row: CurriculumRow) -> some View {
        if let flag = row.untouched {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .help("\(flag.text). Flagged after \(flag.days) days.")
                .accessibilityLabel("Untouched: \(flag.text)")
        }
        if row.kind != .greatLessonsHeader {
            CurriculumCellGlyph(state: row.summary.state, recall: row.summary.recall, tint: row.tint, size: 10)
                .help(CurriculumCellGlyph.label(state: row.summary.state, recall: row.summary.recall))
        }
    }

    private func titleFont(_ row: CurriculumRow) -> Font {
        switch row.kind {
        case .greatLessonsHeader, .area: .system(.subheadline, design: .rounded).weight(.bold)
        case .greatLesson, .sequence: .system(.footnote, design: .rounded).weight(.semibold)
        case .lesson: .system(.footnote, design: .rounded)
        }
    }

    @ViewBuilder
    private func contextMenu(_ row: CurriculumRow) -> some View {
        if case .area(let area) = row.kind {
            Menu("Flag Untouched After…") {
                ForEach(CurriculumMapSettings.untouchedChoices, id: \.self) { days in
                    Button {
                        onSetUntouched(area, days)
                    } label: {
                        if settings.hasOverride(for: area), settings.untouchedDays(for: area) == days {
                            Label("\(days) days", systemImage: "checkmark")
                        } else {
                            Text("\(days) days")
                        }
                    }
                }
                Divider()
                Button("Use Default (\(settings.defaultUntouchedDays) days)") { onSetUntouched(area, nil) }
            }
        }
        if !row.lessonIDs.isEmpty {
            Button("Show Records") { onOpen(row, nil) }
        }
    }
}
