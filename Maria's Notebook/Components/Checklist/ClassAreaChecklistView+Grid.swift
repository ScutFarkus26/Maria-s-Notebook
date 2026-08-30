// ClassAreaChecklistView+Grid.swift
// The checklist's scrollable lesson x student matrix, split out of
// ClassSubjectChecklistView.swift to keep that file focused on layout and actions.

import SwiftUI
import CoreData

// MARK: - Grid

extension ClassAreaChecklistView {
    /// Scroll anchor for one lesson's row. The grid and the reveal below have to
    /// agree on this value, so neither spells it out by hand.
    static func rowAnchor(for lessonID: UUID) -> String {
        "checklist-row-\(lessonID.uuidString)"
    }

    /// The anchor a row actually draws with. A lesson with no UUID can't be
    /// deep-linked to, but it still needs an identity of its own or SwiftUI
    /// would collapse every such row into one.
    static func rowAnchor(for lesson: CDLesson) -> String {
        lesson.id.map { rowAnchor(for: $0) }
            ?? "checklist-row-\(lesson.objectID.uriRepresentation().absoluteString)"
    }

    /// 2D scrollable grid with a pinned header row.
    var grid: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        // Data Rows
                        ForEach(viewModel.visibleSequences, id: \.self) { sequence in
                            sequenceRow(name: sequence)

                            let grouped = viewModel.lessonsSequenced(sequence: sequence)
                            ForEach(grouped.order, id: \.self) { section in
                                if let shLessons = grouped.bySection[section], !shLessons.isEmpty {
                                    if grouped.hasSections {
                                        sectionRow(name: section)
                                    }
                                    ForEach(shLessons) { lesson in
                                        lessonRow(lesson: lesson)
                                            .id(Self.rowAnchor(for: lesson))
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
            .task(id: viewModel.focusedLessonID) {
                await revealFocusedLesson(using: proxy)
            }
        }
    }

    /// Brings a deep-linked row on screen, holds its flash briefly, then clears
    /// it. A change of area rebuilds the grid a beat after the request lands, so
    /// the row is waited for rather than assumed — until the new area's lessons
    /// are on screen there is no anchor to scroll to.
    fileprivate func revealFocusedLesson(using proxy: ScrollViewProxy) async {
        guard let lessonID = viewModel.focusedLessonID else { return }

        func isOnScreen() -> Bool {
            viewModel.visibleLessons.contains { $0.id == lessonID }
        }

        var waited = 0
        while !isOnScreen() && waited < 20 {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            waited += 1
        }

        // The lesson can be missing outright — a card whose lesson was deleted,
        // or one whose area holds no rows. Drop the flash rather than leaving a
        // highlight the guide can never see.
        guard isOnScreen() else {
            viewModel.focusedLessonID = nil
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(Self.rowAnchor(for: lessonID), anchor: .center)
        }

        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.focusedLessonID = nil
        }
    }
}

// MARK: - Lesson Row

extension ClassAreaChecklistView {
    @ViewBuilder
    func lessonRow(lesson: CDLesson) -> some View {
        HStack(spacing: 0) {
            // CDLesson Name (Sticky Left)
            StickyLeftItem(width: lessonColumnWidth, height: rowHeight) {
                lessonNameCell(lesson: lesson)
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

    /// The row's sticky left cell. It also carries the deep-link flash, rather
    /// than the whole row: it is the part that names the lesson, and the one
    /// part horizontal scrolling can never push out of sight.
    private func lessonNameCell(lesson: CDLesson) -> some View {
        let isFocused = lesson.id != nil && lesson.id == viewModel.focusedLessonID
        return VStack(alignment: .leading) {
            Text(lesson.name)
                .font(.system(.body, design: .rounded).weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .padding(.horizontal, 8)
        .frame(width: lessonColumnWidth, height: rowHeight, alignment: .leading)
        .background(isFocused
                    ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                    : Color.clear)
        .backgroundPlatform()
        .overlay {
            if isFocused {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .borderSeparated()
    }
}

// MARK: - Group Rows

extension ClassAreaChecklistView {
    /// The two grouping bands, tallest first. The top-level band is the seam a
    /// guide scans for, so it stands taller and louder than the one below it.
    fileprivate static let sequenceRowHeight: CGFloat = 34
    fileprivate static let sectionRowHeight: CGFloat = 26

    /// An opaque band tinted to `tint`. Both halves of a grouping row — the
    /// sticky left cell and the stretch across the student columns — draw it, so
    /// the tint can't double up where the sticky half slides over the other.
    @ViewBuilder
    fileprivate func groupBand(_ tint: Color) -> some View {
        ZStack {
            Color.clear.backgroundPlatform()
            tint
        }
    }

    /// Top-level grouping — "Preliminary", "Early Work". It rules the full width
    /// of the matrix, in the accent colour and under a heavier line, so a group
    /// boundary is legible however far the grid is scrolled.
    @ViewBuilder
    fileprivate func sequenceRow(name: String) -> some View {
        let height = Self.sequenceRowHeight
        let tint = Color.accentColor.opacity(UIConstants.OpacityConstants.medium)
        HStack(spacing: 0) {
            StickyLeftItem(width: lessonColumnWidth, height: height) {
                HStack(spacing: 0) {
                    Text(name)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .frame(width: lessonColumnWidth, height: height, alignment: .leading)
                .background(groupBand(tint))
                .borderSeparated()
            }

            groupBand(tint)
                .frame(height: height)
                .frame(width: CGFloat(viewModel.students.count) * studentColumnWidth)
                .borderSeparated()
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.semi))
                .frame(height: 2)
                .allowsHitTesting(false)
        }
    }

    /// Second-level grouping inside a sequence — "Chains", "Stamp Game". Indented
    /// and quieter than the band above it, but still heavier than a lesson name.
    @ViewBuilder
    fileprivate func sectionRow(name: String) -> some View {
        let height = Self.sectionRowHeight
        let tint = Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint)
        HStack(spacing: 0) {
            StickyLeftItem(width: lessonColumnWidth, height: height) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.muted))
                        .frame(width: 3, height: 14)
                    Text(name.isEmpty ? "Other" : name)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 24)
                .padding(.trailing, 8)
                .frame(width: lessonColumnWidth, height: height, alignment: .leading)
                .background(groupBand(tint))
                .borderSeparated()
            }

            groupBand(tint)
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
