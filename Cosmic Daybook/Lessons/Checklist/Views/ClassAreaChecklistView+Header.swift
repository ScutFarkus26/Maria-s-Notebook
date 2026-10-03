// ClassAreaChecklistView+Header.swift
// The grid's pinned header. On the Mac and iPad: the area and its counts with
// Collapse all in the corner, a level band over 38-pt columns whose names are angled,
// and the Class column's caption. On the iPhone: names with ages in 120-pt columns.

import SwiftUI

extension ClassAreaChecklistView {

    @ViewBuilder
    func headerRow(students: [CDStudent], metrics: ChecklistGridMetrics) -> some View {
        if metrics.isRegular {
            regularHeaderRow(students: students, metrics: metrics)
        } else {
            compactHeaderRow(students: students, metrics: metrics)
        }
    }

    // MARK: - Mac and iPad

    private func regularHeaderRow(students: [CDStudent], metrics: ChecklistGridMetrics) -> some View {
        let blockStarts = viewModel.columns.blockStartIDs
        return HStack(alignment: .top, spacing: 0) {
            StickyLeftItem(width: metrics.lessonColumnWidth, height: metrics.headerHeight) {
                headerCorner(metrics: metrics)
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
                .padding(.horizontal, 4)
                .frame(
                    width: CGFloat(block.count) * metrics.studentColumnWidth,
                    height: ChecklistGridMetrics.levelBandHeight
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
                .offset(x: 16, y: -8)
                .frame(width: metrics.studentColumnWidth, height: height, alignment: .bottomLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(age.map { "\(student.fullName) · \($0)" } ?? student.fullName)
        .accessibilityLabel(student.fullName)
        .accessibilityHint("Opens the student's record")
    }

    // MARK: - iPhone

    private func compactHeaderRow(students: [CDStudent], metrics: ChecklistGridMetrics) -> some View {
        HStack(spacing: 0) {
            // Top-Left Corner (Sticky horizontally)
            StickyLeftItem(width: metrics.lessonColumnWidth, height: metrics.headerHeight) {
                ZStack {
                    Color.clear.backgroundPlatform()
                    Text("Lessons \\ Students")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: metrics.lessonColumnWidth, height: metrics.headerHeight)
                .borderSeparated()
            }
            .zIndex(100) // Ensure corner stays above everything

            // CDStudent Names (Scrolls Horizontally with content, tappable)
            ForEach(students) { student in
                Button {
                    if let studentID = student.id { AppRouter.shared.requestOpenStudentDetail(studentID) }
                } label: {
                    VStack(spacing: 2) {
                        Text(student.shortName)
                        Text(AgeUtils.conciseAgeString(for: student.birthday ?? Date()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: metrics.studentColumnWidth, height: metrics.headerHeight)
                    .backgroundPlatform()
                    .borderSeparated()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: metrics.rowWidth(studentCount: students.count), alignment: .leading)
    }
}
