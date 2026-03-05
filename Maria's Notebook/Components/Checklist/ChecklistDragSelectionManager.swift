import Foundation
import CoreGraphics

// MARK: - Checklist Drag Selection Manager

/// Manages drag selection state and logic for the checklist grid.
/// Handles converting drag gestures into cell selections.
@Observable
@MainActor
final class ChecklistDragSelectionManager {

    // MARK: - State

    var cellFrames: [CellIdentifier: CGRect] = [:]
    var dragStart: CGPoint?
    var dragCurrent: CGPoint?
    var isDragging: Bool = false

    // MARK: - Selection Calculation

    /// Calculates which cells are selected based on the current drag rectangle.
    ///
    /// - Returns: Set of CellIdentifiers that intersect with the drag rectangle
    func calculateSelectedCells() -> Set<CellIdentifier> {
        guard let start = dragStart, let current = dragCurrent else {
            return []
        }

        let dragRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        var selection = Set<CellIdentifier>()
        for (cellId, frame) in cellFrames {
            if dragRect.intersects(frame) {
                selection.insert(cellId)
            }
        }

        return selection
    }

    // MARK: - Gesture Handling

    /// Called when a drag gesture starts.
    func startDrag(at location: CGPoint) {
        dragStart = location
        isDragging = true
    }

    /// Called when a drag gesture continues.
    func updateDrag(to location: CGPoint) {
        dragCurrent = location
    }

    /// Called when a drag gesture ends.
    func endDrag() {
        dragStart = nil
        dragCurrent = nil
        isDragging = false
    }

    // MARK: - Frame Updates

    /// Updates the stored frame for a cell.
    func updateCellFrame(_ cellId: CellIdentifier, frame: CGRect) {
        cellFrames[cellId] = frame
    }

    /// Updates all cell frames at once.
    func updateAllCellFrames(_ frames: [CellIdentifier: CGRect]) {
        cellFrames = frames
    }

    // MARK: - Reset

    /// Resets all drag state.
    func reset() {
        cellFrames = [:]
        dragStart = nil
        dragCurrent = nil
        isDragging = false
    }
}
