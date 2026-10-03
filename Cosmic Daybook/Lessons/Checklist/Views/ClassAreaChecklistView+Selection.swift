// ClassAreaChecklistView+Selection.swift
// What the grid does with a cell's actions that reach past the view model: reading
// ⌘ / Shift on a click, opening the present-a-lesson and new-work sheets, the
// lesson and the student; a drag across a row or down a column (Mac); and the
// floating selection bar on the Mac and iPad.

import SwiftUI
import CoreData

extension ClassAreaChecklistView {

    /// The column students' IDs in drawing order.
    var columnStudentIDs: [UUID] { columnStudents.compactMap(\.id) }

    // MARK: - Cell Actions

    /// The one handler every cell (and its card) sends its actions through.
    var cellActionHandler: ChecklistCellActionHandler {
        ChecklistCellActionHandler { action, cell in
            handleCellAction(action, on: cell)
        }
    }

    func handleCellAction(_ action: ChecklistCellAction, on cell: CellIdentifier) {
        switch action {
        case .click:
            if usesRegularLayout { isGridFocused = true }
            viewModel.handleClick(
                cell,
                kind: usesRegularLayout ? ChecklistClickModifiers.current : .plain,
                studentOrder: columnStudentIDs,
                context: viewContext
            )
        case .present:
            presentFromCard(cell)
        case .assignWork:
            afterClosingCard {
                workTarget = ChecklistWorkTarget(
                    lessonID: cell.lessonID, studentIDs: [cell.studentID], fromSelection: false
                )
            }
        case .openLesson:
            viewModel.closeCard()
            AppRouter.shared.navigateToLesson(cell.lessonID)
        case .openStudent:
            viewModel.closeCard()
            AppRouter.shared.requestOpenStudentDetail(cell.studentID)
        default:
            viewModel.perform(action, on: cell, context: viewContext)
        }
    }

    /// The card's Present: a draft for this child and the others ready, in the sheet.
    private func presentFromCard(_ cell: CellIdentifier) {
        let studentIDs = viewModel.presentationStudentIDs(for: cell, studentOrder: columnStudentIDs)
        guard let draft = viewModel.makePresentationDraft(
            lessonID: cell.lessonID, studentIDs: studentIDs, context: viewContext
        ) else { return }
        afterClosingCard {
            presentationTarget = ChecklistPresentationTarget(assignment: draft, fromSelection: false)
        }
    }

    /// Closes the card, then opens a sheet once the popover has gone: iPadOS refuses a
    /// sheet while a popover is still leaving.
    func afterClosingCard(_ open: @escaping () -> Void) {
        guard viewModel.cardCell != nil else {
            open()
            return
        }
        viewModel.closeCard()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            open()
        }
    }

    // MARK: - Sheets

    /// After the new-work sheet: the grid catches up, and a sheet from the selection ends it.
    func finishSheet(fromSelection: Bool) {
        viewModel.recomputeMatrix(context: viewContext)
        viewModel.refreshCardRecord(context: viewContext)
        if fromSelection { viewModel.clearSelection() }
    }

    /// After the present-a-lesson sheet: a draft it didn't record or schedule goes, then
    /// the grid catches up.
    func finishPresentation(_ target: ChecklistPresentationTarget) {
        viewModel.discardUnusedDraft(target.assignment, context: viewContext)
        finishSheet(fromSelection: target.fromSelection)
    }

    // MARK: - Drag to Select (Mac)

    var cellDragHandler: ChecklistCellDragHandler {
        ChecklistCellDragHandler(
            changed: { origin, start, translation in
                dragChanged(from: origin, start: start, translation: translation)
            },
            ended: { _ in dragBase = nil }
        )
    }

    /// A drag along the row reaches the column under the pointer; down the column, the row
    /// under it (read from the row layout, as bands and captions space rows unevenly).
    /// With ⌘ held it adds to the selection, otherwise it replaces it.
    private func dragChanged(from origin: CellIdentifier, start: CGPoint, translation: CGSize) {
        if dragBase == nil {
            dragBase = ChecklistClickModifiers.current == .toggle ? viewModel.selectedCells : []
        }
        let metrics = metrics
        let order = columnStudentIDs
        var target = origin
        if abs(translation.width) >= abs(translation.height) {
            guard let index = order.firstIndex(of: origin.studentID) else { return }
            let offset = Int(((start.x + translation.width) / metrics.studentColumnWidth).rounded(.down))
            let column = min(max(index + offset, 0), order.count - 1)
            target = CellIdentifier(studentID: order[column], lessonID: origin.lessonID)
        } else {
            let layout = viewModel.rowLayout(metrics: metrics)
            guard let top = layout.top(of: origin.lessonID),
                  let lessonID = layout.lesson(
                    atY: top + start.y + translation.height, towardTop: translation.height > 0
                  )
            else { return }
            target = CellIdentifier(studentID: origin.studentID, lessonID: lessonID)
        }
        viewModel.dragSelect(from: origin, to: target, base: dragBase ?? [], studentOrder: order)
    }

    // MARK: - Floating Selection Bar

    var floatingSelectionBar: some View {
        let lessonName = viewModel.selectedCellsSameLessonID.flatMap { id in
            viewModel.lessons.first { $0.id == id }?.name
        }
        return ChecklistSelectionBar(
            count: viewModel.selectedCells.count,
            lessonName: lessonName,
            perform: performSelectionAction
        )
    }

    func performSelectionAction(_ action: ChecklistSelectionBarAction) {
        switch action {
        case .presentGroup:
            guard let lessonID = viewModel.selectedCellsSameLessonID,
                  let draft = viewModel.makePresentationDraft(
                    lessonID: lessonID, studentIDs: Array(viewModel.selectedStudentIDs), context: viewContext
                  )
            else { return }
            presentationTarget = ChecklistPresentationTarget(assignment: draft, fromSelection: true)
        case .presented: viewModel.batchMarkPresented(context: viewContext)
        case .mastered: viewModel.batchMarkProficient(context: viewContext)
        case .addToInbox: viewModel.batchAddToInbox(context: viewContext)
        case .previouslyPresented: viewModel.batchMarkPreviouslyPresented(context: viewContext)
        case .addWork:
            guard let lessonID = viewModel.selectedCellsSameLessonID else { return }
            workTarget = ChecklistWorkTarget(
                lessonID: lessonID, studentIDs: viewModel.selectedStudentIDs, fromSelection: true
            )
        case .clear: viewModel.batchClearStatus(context: viewContext)
        case .dismiss: viewModel.clearSelection()
        }
    }
}
