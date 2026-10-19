// ClassGridYearsGrid.swift
// Three Years' grid: a header row pinned by the lazy stack (the area, a
// "YEAR 3 · 5" band over angled names, the Not yet column), a name column
// pinned by the one scroll-offset reading, band rows, and a mark per child.

import SwiftUI

// MARK: - Metrics

/// Three Years' sizes: the Checklist's 38-pt columns under angled names on the
/// Mac and iPad, 44-pt ones on the iPhone, with a Not yet column on the right
/// where there's room.
struct ClassGridYearsMetrics: Equatable {
    let isRegular: Bool
    let labelWidth: CGFloat
    let columnWidth: CGFloat
    let rowHeight: CGFloat
    let bandHeight: CGFloat
    let headerHeight: CGFloat
    /// 0 when there's no Not yet column.
    let notYetWidth: CGFloat

    static let regular = ClassGridYearsMetrics(
        isRegular: true, labelWidth: 240, columnWidth: ChecklistGridMetrics.regular.studentColumnWidth,
        rowHeight: 34, bandHeight: 30, headerHeight: ChecklistGridMetrics.regular.headerHeight, notYetWidth: 116
    )

    static let compact = ClassGridYearsMetrics(
        isRegular: false, labelWidth: ChecklistGridMetrics.compact.lessonColumnWidth,
        columnWidth: ChecklistGridMetrics.compact.studentColumnWidth,
        rowHeight: 44, bandHeight: 32, headerHeight: ChecklistGridMetrics.compact.headerHeight, notYetWidth: 0
    )

    func rowWidth(columns: Int) -> CGFloat {
        labelWidth + CGFloat(columns) * columnWidth + notYetWidth
    }
}

// MARK: - Grid

struct ClassGridYearsGrid: View {
    let model: ClassGridYearsModel
    let areaTitle: String?
    let metrics: ClassGridYearsMetrics
    let onRow: (ClassRow) -> Void
    let onCell: (ClassRow, ClassColumn) -> Void

    var body: some View {
        let columns = model.columns
        let width = metrics.rowWidth(columns: columns.count)
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(model.rows) { row in
                        if row.isBand {
                            band(row, width: width)
                        } else {
                            lessonRow(row, columns: columns)
                        }
                    }
                } header: {
                    header(columns: columns, width: width)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .background(ChecklistGridMetrics.surface)
        .contentMargins(.bottom, ChecklistStatusBar.gridBottomMargin(isRegular: metrics.isRegular), for: .scrollContent)
        .stickyLeftScrollTracking()
    }

    // MARK: Header

    private func header(columns: [ClassColumn], width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            StickyLeftItem(width: metrics.labelWidth, height: metrics.headerHeight) {
                corner
            }
            .zIndex(100)

            VStack(spacing: 0) {
                yearBand
                HStack(spacing: 0) {
                    ForEach(columns) { column in
                        ClassGridAngledName(
                            name: column.shortName, help: "\(column.student.fullName) · \(column.badge)",
                            studentID: column.id,
                            width: metrics.columnWidth,
                            height: metrics.headerHeight - ChecklistGridMetrics.levelBandHeight
                        )
                        .modifier(ChecklistCellRules(
                            isRegular: true, startsBlock: model.blockStartIDs.contains(column.id)
                        ))
                    }
                }
            }

            if metrics.notYetWidth > 0 {
                Text("NOT YET")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                    .padding(.bottom, 12)
                    .frame(width: metrics.notYetWidth, height: metrics.headerHeight, alignment: .bottomLeading)
                    .overlay(alignment: .leading) { ChecklistGridMetrics.hairline.frame(width: 1) }
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, alignment: .leading)
        .background(ChecklistGridMetrics.surface)
        .overlay(alignment: .bottom) {
            ChecklistGridMetrics.blockRule.frame(height: 1).allowsHitTesting(false)
        }
    }

    private var corner: some View {
        VStack(alignment: .leading, spacing: 3) {
            if metrics.isRegular {
                Text(areaTitle ?? "All areas")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(areaTitle == nil
                     ? "Furthest mark per child · oldest first"
                     : "\(model.lessonCount) lesson\(model.lessonCount == 1 ? "" : "s") · oldest first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.leading, metrics.isRegular ? 20 : 16)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .frame(width: metrics.labelWidth, height: metrics.headerHeight, alignment: .bottomLeading)
        .background(ChecklistGridMetrics.surface)
    }

    /// One band per year in class over its columns: "YEAR 3 · 5", the oldest the
    /// most tinted.
    private var yearBand: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.yearBlocks.enumerated()), id: \.element.id) { index, block in
                ViewThatFits(in: .horizontal) {
                    Text(block.title)
                    Text(CurriculumTimeline.yearBadge(block.year).uppercased())
                    Text("\(block.year)")
                }
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(width: CGFloat(block.count) * metrics.columnWidth, height: ChecklistGridMetrics.levelBandHeight)
                .background(Color.blue.opacity(Self.yearTint(block.year)))
                .background(ChecklistGridMetrics.surface)
                .overlay(alignment: .leading) {
                    if index > 0 { ChecklistGridMetrics.blockRule.frame(width: 1) }
                }
                .accessibilityLabel("\(CurriculumTimeline.yearBadge(block.year)), \(block.count) children")
            }
        }
    }

    static func yearTint(_ year: Int) -> Double {
        switch year {
        case 3...: 0.09
        case 2: 0.06
        default: 0.035
        }
    }

    // MARK: Rows

    private func band(_ row: ClassRow, width: CGFloat) -> some View {
        // The band's words may run past the name column; they stay in view as it scrolls.
        let labelWidth = min(width, metrics.labelWidth * 2)
        return HStack(spacing: 0) {
            StickyLeftItem(width: labelWidth, height: metrics.bandHeight) {
                HStack(spacing: 8) {
                    Text(row.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 14)
                .frame(width: labelWidth, height: metrics.bandHeight, alignment: .leading)
                .background(ChecklistGridMetrics.bandFill)
                .background(ChecklistGridMetrics.surface)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            ChecklistGridMetrics.bandFill
                .background(ChecklistGridMetrics.surface)
                .frame(width: width - labelWidth, height: metrics.bandHeight)
        }
        .overlay(alignment: .top) { ChecklistGridMetrics.blockRule.frame(height: 1).allowsHitTesting(false) }
        .overlay(alignment: .bottom) { ChecklistGridMetrics.hairline.frame(height: 0.5).allowsHitTesting(false) }
    }

    private func lessonRow(_ row: ClassRow, columns: [ClassColumn]) -> some View {
        HStack(spacing: 0) {
            StickyLeftItem(width: metrics.labelWidth, height: metrics.rowHeight) {
                label(row)
            }
            ForEach(columns) { column in
                ClassGridYearsCell(
                    spec: row.cells[column.id],
                    label: "\(column.student.fullName), \(row.title)",
                    isEnabled: !row.lessonIDs.isEmpty,
                    onTap: { onCell(row, column) }
                )
                .equatable()
                .frame(width: metrics.columnWidth, height: metrics.rowHeight)
                .modifier(ChecklistCellRules(
                    isRegular: metrics.isRegular, startsBlock: model.blockStartIDs.contains(column.id)
                ))
            }
            if metrics.notYetWidth > 0 {
                Text(row.lessonIDs.isEmpty ? "—" : row.notYetText(over: columns))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                    .frame(width: metrics.notYetWidth, height: metrics.rowHeight, alignment: .leading)
                    .overlay(alignment: .leading) { ChecklistGridMetrics.hairline.frame(width: 1) }
                    .help("Children with nothing recorded on this row")
            }
        }
        .overlay(alignment: .bottom) {
            if metrics.isRegular {
                ChecklistGridMetrics.hairline.frame(height: 0.5).allowsHitTesting(false)
            }
        }
    }

    /// The row's name with its area's color, and what it holds; a click lists the
    /// children in each state.
    private func label(_ row: ClassRow) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(row.tint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(metrics.isRegular ? .subheadline : .footnote)
                    .lineLimit(metrics.isRegular ? 1 : 2)
                if metrics.isRegular, let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, metrics.isRegular ? 18 : 16)
        .padding(.trailing, 8)
        .frame(width: metrics.labelWidth, height: metrics.rowHeight, alignment: .leading)
        .background(ChecklistGridMetrics.surface)
        .modifier(ChecklistCellRules(isRegular: metrics.isRegular, startsBlock: false))
        .contentShape(Rectangle())
        .onTapGesture {
            if !row.lessonIDs.isEmpty { onRow(row) }
        }
        .help(row.subtitle.map { "\(row.title) — \($0)" } ?? row.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the children in each state")
    }
}

/// One child's mark on one row. Equatable, so a rebuild redraws only the cells
/// whose mark changed.
private struct ClassGridYearsCell: View, Equatable {
    let spec: CurriculumGlyphSpec?
    let label: String
    let isEnabled: Bool
    let onTap: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.spec == rhs.spec && lhs.label == rhs.label && lhs.isEnabled == rhs.isEnabled
    }

    var body: some View {
        let state = spec?.state ?? .notReady
        Button(action: onTap) {
            ChecklistMark(status: state, recall: spec?.recall, size: 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityValue(ChecklistMark.label(status: state, recall: spec?.recall))
    }
}
