// ClassAreaChecklistView+Keyboard.swift
// The grid's plain keys on the Mac and iPad (ChecklistKeyCommand): arrows move the
// cursor, Return or Space opens its card, P / M / I / Delete act on its cell, Escape
// closes the card, then drops the selection, then the cursor. Read only while the
// grid has focus; a click on a cell gives it focus.

import SwiftUI

extension ClassAreaChecklistView {

    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard usesRegularLayout,
              let command = ChecklistKeyCommand.command(
                key: press.key, characters: press.characters, modifiers: press.modifiers
              )
        else { return .ignored }

        switch command {
        case .move(let dx, let dy):
            viewModel.closeCard()
            viewModel.moveCursor(dx: dx, dy: dy, studentOrder: columnStudentIDs)
        case .openCard:
            guard let cell = viewModel.cursorCell else {
                viewModel.moveCursor(dx: 0, dy: 0, studentOrder: columnStudentIDs)
                return .handled
            }
            viewModel.openCard(cell, context: viewContext)
        case .dismiss:
            return dismissOne() ? .handled : .ignored
        case .presented, .mastered, .toggleInbox, .clear:
            guard let cell = viewModel.cursorCell, let action = command.cellAction else { return .ignored }
            viewModel.perform(action, on: cell, context: viewContext)
        }
        return .handled
    }

    /// Escape backs out one step: the card, else the selection, else the cursor.
    private func dismissOne() -> Bool {
        if viewModel.cardCell != nil {
            viewModel.closeCard()
        } else if !viewModel.selectedCells.isEmpty {
            viewModel.clearSelection()
        } else if viewModel.cursorCell != nil {
            viewModel.cursorCell = nil
        } else {
            return false
        }
        return true
    }
}
