// ClassSubjectChecklistViewModel+SubAreaOrder.swift
// Move Up / Move Down on a sequence band: the guide sets the order of the area's
// sub-areas from the grid itself. The order is the one the Lessons map and the MCP
// tools read (`SubAreaOrder`), so a move here shows there too.

import Foundation

extension ClassAreaChecklistViewModel {

    /// Whether `sequence`'s band can move `step` places (-1 up, +1 down) among the
    /// bands on screen.
    func canMoveSequence(_ sequence: String, by step: Int) -> Bool {
        SubAreaOrder.moving(sequence, by: step, visible: visibleSequences, in: orderedSequences) != nil
    }

    /// Moves `sequence`'s band one place up (-1) or down (+1) past the next band on
    /// screen and saves the area's new order. A band a lesson search hides keeps its slot.
    func moveSequence(_ sequence: String, by step: Int) {
        guard !selectedArea.trimmed().isEmpty,
              let order = SubAreaOrder.moving(sequence, by: step, visible: visibleSequences, in: orderedSequences)
        else { return }
        SubAreaOrder.save(order, area: selectedArea)
        orderedSequences = order
        applyFilters()
    }
}
