// ClassAreaChecklistView+Grid.swift
// The checklist's scrollable lesson x student matrix, split out of
// ClassSubjectChecklistView.swift to keep that file focused on layout and actions.
// The bands are in +Bands, the pinned header in +Header.

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

    /// Scroll anchor for a sequence band, for "Jump to sequence".
    static func bandAnchor(for sequence: String) -> String {
        "checklist-band-\(sequence)"
    }

    /// The student columns in drawing order: level blocks on the Mac and iPad, the
    /// roster's birthday order on the iPhone.
    var columnStudents: [CDStudent] {
        usesRegularLayout ? viewModel.columns.students : viewModel.students
    }

    /// 2D scrollable grid with a pinned header row.
    var grid: some View {
        let metrics = metrics
        let students = columnStudents
        let columnIDs = students.compactMap(\.id)
        return ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(viewModel.visibleSequences, id: \.self) { sequence in
                            sequenceRows(sequence, students: students, metrics: metrics)
                        }
                    } header: {
                        // Pinned header row - stays at top during vertical scroll
                        headerRow(students: students, metrics: metrics)
                    }
                }
                // The pointer's column, behind every row; bands, names and header cover it.
                .background(alignment: .topLeading) {
                    if metrics.isRegular {
                        ChecklistColumnHoverStripe(columnIDs: columnIDs, metrics: metrics)
                    }
                }
            }
            .background(gridSurface)
            .environment(hover)
            .environment(viewModel)
            .focusable(usesRegularLayout)
            .focusEffectDisabled()
            .focused($isGridFocused)
            .onKeyPress(phases: .down) { press in handleKey(press) }
            // Room for the last rows to scroll clear of the app's floating button.
            .contentMargins(
                .bottom, ChecklistStatusBar.gridBottomMargin(isRegular: metrics.isRegular),
                for: .scrollContent
            )
            .stickyLeftScrollTracking()
            .onScrollGeometryChange(for: CGSize.self) { geometry in
                geometry.containerSize
            } action: { _, size in
                gridViewportHeight = size.height
                gridViewportWidth = size.width
            }
            // Keys move the cursor off screen; bring its row back (the least scroll that does).
            .onChange(of: viewModel.cursorCell?.lessonID) { _, lessonID in
                guard let lessonID, viewModel.cardCell == nil else { return }
                proxy.scrollTo(Self.rowAnchor(for: lessonID))
            }
            .task(id: viewModel.focusedLessonID) {
                await revealFocusedLesson(using: proxy)
            }
            .task(id: sequenceJump) {
                await performSequenceJump(using: proxy)
            }
        }
    }

    /// What the grid draws on: white on the Mac and iPad, the grouped grey on the iPhone.
    var gridSurface: Color {
        metrics.isRegular ? ChecklistGridMetrics.surface : Color.controlBackgroundColor()
    }

    /// One sequence: its band, then (unless folded) its section captions and lessons.
    @ViewBuilder
    private func sequenceRows(_ sequence: String, students: [CDStudent], metrics: ChecklistGridMetrics) -> some View {
        let grouped = viewModel.lessonsSequenced(sequence: sequence)
        let isCollapsed = viewModel.isCollapsed(sequence)
        sequenceRow(
            name: sequence, lessonCount: grouped.lessonCount, isCollapsed: isCollapsed,
            studentCount: students.count, metrics: metrics
        )
        .id(Self.bandAnchor(for: sequence))

        if !isCollapsed {
            ForEach(grouped.order, id: \.self) { section in
                if let shLessons = grouped.bySection[section], !shLessons.isEmpty {
                    if grouped.hasSections {
                        sectionRow(name: section, studentCount: students.count, metrics: metrics)
                    }
                    // A caption already names the section, so its lessons drop it
                    // from the front of their names.
                    let caption = grouped.hasSections ? section : ""
                    ForEach(shLessons) { lesson in
                        lessonRow(lesson: lesson, sectionCaption: caption, students: students, metrics: metrics)
                            .id(Self.rowAnchor(for: lesson))
                    }
                }
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

        // A folded band has no rows to scroll to: open it and let them draw first.
        if viewModel.expandSequence(containing: lessonID) {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(Self.rowAnchor(for: lessonID), anchor: UnitPoint(x: 0, y: 0.5))
        }

        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.focusedLessonID = nil
        }
    }

    /// Scrolls a band picked from "Jump to sequence" to just under the pinned header,
    /// opening it first if it was folded.
    fileprivate func performSequenceJump(using proxy: ScrollViewProxy) async {
        guard let jump = sequenceJump else { return }
        if viewModel.expandSequence(jump.sequence) {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
        }
        // scrollTo lines the band's anchor point up with the same point of the view:
        // solve for the band's top landing at the header's bottom edge.
        let metrics = metrics
        let free = gridViewportHeight - metrics.sequenceBandHeight
        let fraction = free > metrics.headerHeight ? metrics.headerHeight / free : 0
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(Self.bandAnchor(for: jump.sequence), anchor: UnitPoint(x: 0, y: fraction))
        }
    }
}

// MARK: - Lesson Row

extension ClassAreaChecklistView {
    @ViewBuilder
    func lessonRow(
        lesson: CDLesson, sectionCaption: String, students: [CDStudent], metrics: ChecklistGridMetrics
    ) -> some View {
        let handler = cellActionHandler
        let dragHandler = cellDragHandler
        let isSelectionMode = viewModel.isSelectionMode
        let precedingLessonName = lesson.id.flatMap { viewModel.precedingLessonNames[$0] }
        let blockStarts = metrics.isRegular ? viewModel.columns.blockStartIDs : []
        let cursor = isGridFocused && metrics.isRegular ? viewModel.cursorCell : nil
        let cardCell = viewModel.cardCell
        let lens = viewModel.lens
        HStack(spacing: 0) {
            // CDLesson Name (Sticky Left)
            StickyLeftItem(width: metrics.lessonColumnWidth, height: metrics.rowHeight) {
                lessonNameCell(lesson: lesson, sectionCaption: sectionCaption, metrics: metrics)
            }

            // Grid Cells
            ForEach(students) { student in
                let cell = cellIdentifier(student: student, lesson: lesson)
                ClassChecklistSmartCell(
                    cell: cell,
                    state: viewModel.state(for: student, lesson: lesson),
                    isSelected: viewModel.isSelected(student: student, lesson: lesson),
                    isSelectionMode: isSelectionMode,
                    isCursor: cursor == cell,
                    isCardOpen: cardCell == cell,
                    isRegular: metrics.isRegular,
                    studentName: student.shortName,
                    lessonName: lesson.name,
                    precedingLessonName: precedingLessonName,
                    lens: lens,
                    onAction: handler,
                    onDrag: dragHandler
                )
                .equatable()
                .frame(width: metrics.studentColumnWidth, height: metrics.rowHeight)
                .modifier(ChecklistCellRules(
                    isRegular: metrics.isRegular,
                    startsBlock: student.id.map(blockStarts.contains) ?? false
                ))
            }

            if metrics.classColumnWidth > 0 {
                ChecklistClassCell(
                    summary: lesson.id.flatMap { viewModel.rowSummaries[$0] } ?? ChecklistRowSummary(),
                    lens: lens,
                    onPlan: { planReady(lessonID: lesson.id) }
                )
                .equatable()
                .frame(width: metrics.classColumnWidth, height: metrics.rowHeight)
            }
        }
        .modifier(ChecklistRowChrome(lessonID: lesson.id, columnIDs: students.compactMap(\.id), metrics: metrics))
    }

    /// A record with no ID gets the nil UUID, which no student or lesson carries, so its
    /// cell draws empty and its actions find nothing to act on, as before.
    private func cellIdentifier(student: CDStudent, lesson: CDLesson) -> CellIdentifier {
        let none = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        return CellIdentifier(studentID: student.id ?? none, lessonID: lesson.id ?? none)
    }

    /// The row's sticky left cell. It also carries the deep-link flash, rather
    /// than the whole row: it is the part that names the lesson, and the one
    /// part horizontal scrolling can never push out of sight. Under a section
    /// caption it shows the name without the section's; hover text and VoiceOver
    /// keep the full name.
    private func lessonNameCell(
        lesson: CDLesson, sectionCaption: String, metrics: ChecklistGridMetrics
    ) -> some View {
        let isFocused = lesson.id != nil && lesson.id == viewModel.focusedLessonID
        let shown = ChecklistLessonDisplayName.displayName(lessonName: lesson.name, section: sectionCaption)
        // The Ready lens greys a row with no one ready for it.
        let readyCount = viewModel.isReadyLens ? viewModel.readyCount(for: lesson.id) : 0
        return HStack(spacing: 6) {
            ChecklistLessonNameText(
                lessonID: lesson.id,
                text: shown,
                font: metrics.isRegular
                    ? .system(.subheadline)
                    : .system(.body, design: .rounded).weight(.medium),
                lineLimit: metrics.isRegular ? 1 : 2,
                isDimmed: viewModel.isReadyLens && readyCount == 0
            )
            .minimumScaleFactor(metrics.isRegular ? 1 : 0.9)
            .frame(maxWidth: .infinity, alignment: .leading)

            if metrics.isRegular {
                ChecklistSelectReadyButton(lessonID: lesson.id, studentOrder: columnStudentIDs) { lessonID in
                    viewModel.selectReady(in: lessonID, studentOrder: columnStudentIDs)
                }
            } else if readyCount > 0 {
                // The iPhone has no Class column: the row's Plan sits by its name.
                ChecklistCompactPlanButton(readyCount: readyCount) { planReady(lessonID: lesson.id) }
            }
        }
        .padding(.leading, metrics.isRegular ? 32 : 8)
        .padding(.trailing, metrics.isRegular ? 10 : 8)
        .frame(width: metrics.lessonColumnWidth, height: metrics.rowHeight, alignment: .leading)
        .background(isFocused
                    ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                    : Color.clear)
        .background { ChecklistNameHoverTint(lessonID: lesson.id) }
        .background(gridSurface)
        .modifier(ChecklistNameHoverTracking(isEnabled: metrics.isRegular, lessonID: lesson.id, hover: hover))
        .overlay {
            if isFocused {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .modifier(ChecklistCellRules(isRegular: metrics.isRegular, startsBlock: false))
        .help(lesson.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lesson.name)
    }
}

// MARK: - Cell Rules

/// The lines around a cell. The iPhone keeps its full grid of hairlines; the Mac and
/// iPad draw only the row's bottom hairline (on the row) and a heavier rule where one
/// level block of columns meets the next.
struct ChecklistCellRules: ViewModifier {
    let isRegular: Bool
    let startsBlock: Bool

    func body(content: Content) -> some View {
        if isRegular {
            content.overlay(alignment: .leading) {
                if startsBlock {
                    ChecklistGridMetrics.blockRule
                        .frame(width: 1)
                        .allowsHitTesting(false)
                }
            }
        } else {
            content.borderSeparated()
        }
    }
}
