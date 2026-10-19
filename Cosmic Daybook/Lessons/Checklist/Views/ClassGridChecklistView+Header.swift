// ClassGridChecklistView+Header.swift
// The grid's pinned header: a level band over the columns, whose names are angled,
// in 38-pt columns on the Mac and iPad and 44-pt ones on the iPhone. On the Mac and
// iPad the corner holds the area and its counts with Collapse all, and the Class
// column has its caption; on the iPhone the corner counts each level.

import SwiftUI

extension ClassGridChecklistView {

    func headerRow(students: [CDStudent], metrics: ChecklistGridMetrics) -> some View {
        let blockStarts = viewModel.columns.blockStartIDs
        return HStack(alignment: .top, spacing: 0) {
            StickyLeftItem(width: metrics.lessonColumnWidth, height: metrics.headerHeight) {
                Group {
                    if metrics.isRegular {
                        headerCorner(metrics: metrics)
                    } else {
                        compactCorner(metrics: metrics)
                    }
                }
            }
            .zIndex(100) // Ensure corner stays above everything

            VStack(spacing: 0) {
                levelBand(metrics: metrics)
                HStack(spacing: 0) {
                    ForEach(students) { student in
                        angledNameButton(student: student, metrics: metrics)
                            .modifier(ChecklistCellRules(
                                isRegular: true,
                                startsBlock: student.id.map(blockStarts.contains) ?? false
                            ))
                    }
                }
            }

            if metrics.classColumnWidth > 0 {
                Text("CLASS")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                    .padding(.bottom, 12)
                    .frame(width: metrics.classColumnWidth, height: metrics.headerHeight, alignment: .bottomLeading)
                    .overlay(alignment: .leading) {
                        ChecklistGridMetrics.hairline.frame(width: 1)
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(width: metrics.rowWidth(studentCount: students.count), alignment: .leading)
        .background(gridSurface)
        .overlay(alignment: .bottom) {
            ChecklistGridMetrics.blockRule
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    /// The area's name, what it holds, and Collapse all / Expand all.
    private func headerCorner(metrics: ChecklistGridMetrics) -> some View {
        let area = viewModel.selectedArea.trimmed()
        let lessons = viewModel.visibleLessons.count
        let sequences = viewModel.visibleSequences.count
        let allCollapsed = viewModel.areAllSequencesCollapsed
        return VStack(alignment: .leading, spacing: 3) {
            Text(area.isEmpty ? "Checklist" : area)
                .font(.title3.weight(.bold))
                .lineLimit(1)
            HStack(spacing: 0) {
                // A lesson column narrowed to fit the class drops the sequence count first.
                let lessonCount = "\(lessons) lesson\(lessons == 1 ? "" : "s")"
                ViewThatFits(in: .horizontal) {
                    Text("\(lessonCount) · \(sequences) sequence\(sequences == 1 ? "" : "s")")
                    Text(lessonCount)
                }
                .foregroundStyle(.secondary)
                if !viewModel.isSearchingLessons {
                    Text(" · ").foregroundStyle(.secondary)
                    Button(allCollapsed ? "Expand all" : "Collapse all") {
                        withAnimation(.snappy(duration: 0.2)) {
                            viewModel.setAllSequencesCollapsed(!allCollapsed)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .help(allCollapsed ? "Show every sequence's lessons" : "Fold every sequence to its band")
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .frame(width: metrics.lessonColumnWidth, height: metrics.headerHeight, alignment: .bottomLeading)
        .background(gridSurface)
    }

    /// One labeled block per level over its columns: "UPPER ELEMENTARY · 16".
    private func levelBand(metrics: ChecklistGridMetrics) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(viewModel.columns.blocks.enumerated()), id: \.element.id) { index, block in
                ViewThatFits(in: .horizontal) {
                    Text("\(block.level.title.uppercased()) · \(block.count)")
                    Text("\(block.level.rawValue.uppercased()) · \(block.count)")
                    Text("\(block.count)")
                }
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, metrics.isRegular ? 4 : 10)
                // The iPhone shows a few columns of a block at a time: its label sits at
                // the block's start, where the first columns are.
                .frame(
                    width: CGFloat(block.count) * metrics.studentColumnWidth,
                    height: ChecklistGridMetrics.levelBandHeight,
                    alignment: metrics.isRegular ? .center : .leading
                )
                .background(ChecklistGridMetrics.bandFill)
                .overlay(alignment: .leading) {
                    if index > 0 {
                        ChecklistGridMetrics.blockRule.frame(width: 1)
                    }
                }
                .help("\(block.level.title): \(block.count) student\(block.count == 1 ? "" : "s")")
                .accessibilityLabel("\(block.level.title), \(block.count) students")
            }
        }
    }

    /// A column's name, angled up and to the right. Opens the student; the age is in
    /// the hover text.
    private func angledNameButton(student: CDStudent, metrics: ChecklistGridMetrics) -> some View {
        let height = metrics.headerHeight - ChecklistGridMetrics.levelBandHeight
        let age = student.birthday.map { AgeUtils.conciseAgeString(for: $0) }
        return Button {
            if let studentID = student.id { AppRouter.shared.requestOpenStudentDetail(studentID) }
        } label: {
            ChecklistHeaderName(studentID: student.id, name: student.shortName)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 96, alignment: .leading)
                .rotationEffect(.degrees(-55), anchor: .bottomLeading)
                .offset(x: metrics.studentColumnWidth * 0.42, y: -8)
                .frame(width: metrics.studentColumnWidth, height: height, alignment: .bottomLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(age.map { "\(student.fullName) · \($0)" } ?? student.fullName)
        .accessibilityLabel(student.fullName)
        .accessibilityHint("Opens the student's record")
    }

    // MARK: - iPhone

    /// "Upper · 16", "Adolescent · 6": the iPhone's corner counts each level block.
    private func compactCorner(metrics: ChecklistGridMetrics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(viewModel.columns.blocks) { block in
                Text("\(block.level.rawValue) · \(block.count)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.bottom, 10)
        .frame(width: metrics.lessonColumnWidth, height: metrics.headerHeight, alignment: .bottomLeading)
        .background(gridSurface)
        .accessibilityElement(children: .combine)
    }
}
