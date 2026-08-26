// ClassAreaChecklistView+Grid.swift
// The checklist's scrollable lesson x student matrix, split out of
// ClassSubjectChecklistView.swift to keep that file focused on layout and actions.

import SwiftUI
import CoreData

// MARK: - Grid

extension ClassAreaChecklistView {
    /// 2D scrollable grid with a pinned header row.
    var grid: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    // Data Rows
                    ForEach(viewModel.visibleSequences, id: \.self) { sequence in
                        // Group Header
                        HStack(spacing: 0) {
                            StickyLeftItem(width: lessonColumnWidth, height: 30) {
                                HStack {
                                    Text(sequence)
                                        .font(.system(.caption, design: .rounded).weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .padding(.leading)
                                    Spacer()
                                }
                                .background(Color.secondary.opacity(UIConstants.OpacityConstants.hint))
                                .borderSeparated()
                            }

                            // Spacer for the rest of the sequence row
                            Color.secondary.opacity(UIConstants.OpacityConstants.hint)
                                .frame(height: 30)
                                .frame(width: CGFloat(viewModel.students.count) * studentColumnWidth)
                                .borderSeparated()
                        }

                        let grouped = viewModel.lessonsSequenced(sequence: sequence)
                        ForEach(grouped.order, id: \.self) { section in
                            if let shLessons = grouped.bySection[section], !shLessons.isEmpty {
                                if grouped.hasSections {
                                    sectionRow(name: section)
                                }
                                ForEach(shLessons) { lesson in
                                    lessonRow(lesson: lesson)
                                }
                            }
                        }
                    }
                } header: {
                    // Pinned header row - stays at top during vertical scroll
                    headerRow
                }
            }
        }
        .coordinateSpace(name: "gridSpace")
    }
}

// MARK: - Lesson Row

extension ClassAreaChecklistView {
    @ViewBuilder
    func lessonRow(lesson: CDLesson) -> some View {
        HStack(spacing: 0) {
            // CDLesson Name (Sticky Left)
            StickyLeftItem(width: lessonColumnWidth, height: rowHeight) {
                VStack(alignment: .leading) {
                    Text(lesson.name)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
                .padding(.horizontal, 8)
                .frame(width: lessonColumnWidth, height: rowHeight, alignment: .leading)
                .backgroundPlatform()
                .borderSeparated()
            }

            // Grid Cells
            ForEach(viewModel.students) { student in
                let state = viewModel.state(for: student, lesson: lesson)
                ClassChecklistSmartCell(
                    state: state,
                    isSelected: viewModel.isSelected(student: student, lesson: lesson),
                    isSelectionMode: viewModel.isSelectionMode,
                    studentName: student.fullName,
                    lessonName: lesson.name,
                    onTap: {
                        viewModel.toggleScheduled(student: student, lesson: lesson, context: viewContext)
                    },
                    onSelect: {
                        viewModel.toggleSelection(student: student, lesson: lesson)
                    },
                    onMarkComplete: {
                        viewModel.markComplete(student: student, lesson: lesson, context: viewContext)
                    },
                    onMarkPresented: {
                        viewModel.togglePresented(student: student, lesson: lesson, context: viewContext)
                    },
                    onMarkPreviouslyPresented: {
                        viewModel.togglePreviouslyPresented(student: student, lesson: lesson, context: viewContext)
                    },
                    onClear: {
                        viewModel.clearStatus(student: student, lesson: lesson, context: viewContext)
                    }
                )
                .frame(width: studentColumnWidth, height: rowHeight)
                .borderSeparated()
            }
        }
    }
}

// MARK: - Section Row

extension ClassAreaChecklistView {
    @ViewBuilder
    fileprivate func sectionRow(name: String) -> some View {
        let height: CGFloat = 24
        HStack(spacing: 0) {
            StickyLeftItem(width: lessonColumnWidth, height: height) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.secondary.opacity(UIConstants.OpacityConstants.semi))
                        .frame(width: 3, height: 12)
                    Text(name.isEmpty ? "Other" : name)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.leading, 24)
                .frame(width: lessonColumnWidth, height: height, alignment: .leading)
                .background(Color.secondary.opacity(UIConstants.OpacityConstants.trace))
                .borderSeparated()
            }

            Color.secondary.opacity(UIConstants.OpacityConstants.trace)
                .frame(height: height)
                .frame(width: CGFloat(viewModel.students.count) * studentColumnWidth)
                .borderSeparated()
        }
    }
}

// MARK: - Header Row

extension ClassAreaChecklistView {
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Top-Left Corner (Sticky horizontally)
            StickyLeftItem(width: lessonColumnWidth, height: rowHeight) {
                ZStack {
                    Color.clear.backgroundPlatform()
                    Text("Lessons \\ Students")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: lessonColumnWidth, height: rowHeight)
                .borderSeparated()
            }
            .zIndex(100) // Ensure corner stays above everything

            // CDStudent Names (Scrolls Horizontally with content, tappable)
            ForEach(viewModel.students) { student in
                Button {
                    if let studentID = student.id { AppRouter.shared.requestOpenStudentDetail(studentID) }
                } label: {
                    VStack(spacing: 2) {
                        Text(viewModel.displayName(for: student))
                        Text(AgeUtils.conciseAgeString(for: student.birthday ?? Date()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: studentColumnWidth, height: rowHeight)
                    .backgroundPlatform()
                    .borderSeparated()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(
            minWidth: lessonColumnWidth + (CGFloat(viewModel.students.count) * studentColumnWidth),
            alignment: .leading
        )
    }
}
