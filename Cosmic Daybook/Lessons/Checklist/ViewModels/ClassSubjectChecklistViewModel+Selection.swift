// ClassAreaChecklistViewModel+Selection.swift
// A click, the keyboard cursor, the cell card and selecting without a mode.
// A plain click opens the cell's card; ⌘-click toggles a cell in the selection;
// Shift-click and a drag reach along a row or down a column (ChecklistSelection);
// "Select ready" picks a lesson's ready children. The iPhone keeps its Select mode,
// where a tap toggles.

import Foundation
import CoreData

extension ClassAreaChecklistViewModel {

    /// How a click on a cell was made.
    enum ClickKind {
        case plain
        /// ⌘ held.
        case toggle
        /// Shift held.
        case extend
    }

    // MARK: - Drawing Order

    /// The lesson rows on screen, top to bottom: visible lessons, minus folded bands.
    var displayedLessonIDs: [UUID] {
        visibleSequences.flatMap { sequence -> [UUID] in
            guard !isCollapsed(sequence) else { return [] }
            let grouped = lessonsSequenced(sequence: sequence)
            return grouped.order.flatMap { grouped.bySection[$0] ?? [] }.compactMap(\.id)
        }
    }

    /// The grid's strips below the header, for a drag down a column to find its row.
    func rowLayout(metrics: ChecklistGridMetrics) -> ChecklistRowLayout {
        var slots: [ChecklistRowLayout.Slot] = []
        for sequence in visibleSequences {
            slots.append(.init(lessonID: nil, height: metrics.sequenceBandHeight))
            guard !isCollapsed(sequence) else { continue }
            let grouped = lessonsSequenced(sequence: sequence)
            for section in grouped.order {
                guard let lessons = grouped.bySection[section], !lessons.isEmpty else { continue }
                if grouped.hasSections {
                    slots.append(.init(lessonID: nil, height: metrics.sectionCaptionHeight))
                }
                // A lesson with no ID still draws a row; it just can't be landed on.
                slots += lessons.map { .init(lessonID: $0.id, height: metrics.rowHeight) }
            }
        }
        return ChecklistRowLayout(slots: slots)
    }

    // MARK: - Clicks

    /// A click on a cell. `studentOrder` is the columns as drawn, for Shift-click.
    func handleClick(
        _ cell: CellIdentifier, kind: ClickKind, studentOrder: [UUID], context: NSManagedObjectContext
    ) {
        cursorCell = cell
        switch kind {
        case .plain where isEditModeActive, .toggle:
            closeCard()
            selectedCells = ChecklistSelection.toggling(cell, in: selectedCells)
            selectionAnchor = cell
        case .extend:
            closeCard()
            let anchor = selectionAnchor ?? cell
            selectedCells.formUnion(ChecklistSelection.range(
                from: anchor, to: cell, lessonOrder: displayedLessonIDs, studentOrder: studentOrder
            ))
        case .plain:
            clearSelection()
            selectionAnchor = cell
            openCard(cell, context: context)
        }
    }

    /// While dragging from `origin`: the selection becomes `base` plus the cells from the
    /// origin to `target` along its row or down its column.
    func dragSelect(
        from origin: CellIdentifier, to target: CellIdentifier,
        base: Set<CellIdentifier>, studentOrder: [UUID]
    ) {
        closeCard()
        let reach = ChecklistSelection.range(
            from: origin, to: target, lessonOrder: displayedLessonIDs, studentOrder: studentOrder
        )
        let selection = base.union(reach)
        if selection != selectedCells { selectedCells = selection }
        selectionAnchor = origin
        cursorCell = target
    }

    /// The ready children of one lesson, as the selection: the name cell's "Select ready".
    func selectReady(in lessonID: UUID, studentOrder: [UUID]) {
        closeCard()
        let cells = readyStudentIDs(for: lessonID, studentOrder: studentOrder)
            .map { CellIdentifier(studentID: $0, lessonID: lessonID) }
        selectedCells = Set(cells)
        selectionAnchor = cells.first
        cursorCell = cells.first ?? cursorCell
    }

    /// The children on screen who are Ready for the lesson, in `studentOrder`.
    func readyStudentIDs(for lessonID: UUID, studentOrder: [UUID], excluding: UUID? = nil) -> [UUID] {
        ChecklistSelection.readyStudents(
            for: lessonID, studentOrder: studentOrder, matrix: matrixStates, excluding: excluding
        )
    }

    // MARK: - Keyboard Cursor

    /// Arrow keys: one cell over or one row down, stopping at the edges.
    func moveCursor(dx: Int, dy: Int, studentOrder: [UUID]) {
        cursorCell = ChecklistSelection.moving(
            cursorCell, dx: dx, dy: dy, lessonOrder: displayedLessonIDs, studentOrder: studentOrder
        )
    }

    // MARK: - Card

    func openCard(_ cell: CellIdentifier, context: NSManagedObjectContext) {
        cardRecord = Self.loadCardRecord(for: cell, context: context)
        cursorCell = cell
        cardCell = cell
    }

    func closeCard() {
        if cardCell != nil { cardCell = nil }
    }

    /// Re-reads the open card's dates after a change made from it.
    func refreshCardRecord(context: NSManagedObjectContext) {
        guard let cardCell else { return }
        let record = Self.loadCardRecord(for: cardCell, context: context)
        if record != cardRecord { cardRecord = record }
    }

    /// When the child was last given the lesson, and when her open plan is for (nil for
    /// the Inbox). One fetch of the lesson's assignments, filtered to her.
    static func loadCardRecord(for cell: CellIdentifier, context: NSManagedObjectContext) -> ChecklistCardRecord {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", cell.lessonID.uuidString)
        let studentKey = cell.studentID.uuidString
        let hers = context.safeFetch(request).filter { $0.studentIDs.contains(studentKey) }
        return ChecklistCardRecord(
            presentedOn: hers.filter(\.isPresented).compactMap(\.presentedAt).max(),
            plannedFor: hers.filter { !$0.isPresented }.compactMap(\.scheduledFor).min()
        )
    }
}
