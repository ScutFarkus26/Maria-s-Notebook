// PlanningDropUtils.swift
// Utilities for computing insertion indices and assigning times for drag/drop in planning views.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import CoreGraphics
import CoreData

/// Helper utilities for drag-and-drop computations in the planning UI.
/// All functions are pure and side-effect free.
enum PlanningDropUtils {
    // MARK: - Insertion
    static func computeInsertionIndex(locationY: CGFloat, frames: [UUID: CGRect]) -> Int {
        let ordered = frames.sorted { $0.value.minY < $1.value.minY }
        for (index, frame) in ordered.enumerated() {
            let midY = frame.value.midY
            if locationY < midY {
                return index
            }
        }
        return ordered.count
    }

    // MARK: - Reordering

    /// Returns `ids` with `movedID` repositioned to where the drop landed.
    ///
    /// Two index spaces have to be reconciled, and getting either wrong puts
    /// the pill one slot from where the indicator promised:
    ///
    /// 1. `frames` still contains the dragged card, so the raw index counts a
    ///    row that is about to be removed. It is dropped from the frame set
    ///    first, so both spaces describe the same list.
    /// 2. Cards scrolled out of a `LazyVStack` never report a frame, so the
    ///    frame set covers only what is on screen. The boundary is therefore
    ///    resolved to an *id* and then looked up in the full list, rather than
    ///    being used as a position directly.
    static func reordered(
        ids: [UUID],
        moving movedID: UUID,
        toLocationY locationY: CGFloat,
        frames: [UUID: CGRect]
    ) -> [UUID] {
        var remaining = ids
        remaining.removeAll { $0 == movedID }

        var visibleFrames = frames
        visibleFrames.removeValue(forKey: movedID)

        let visibleOrder = visibleFrames.sorted { $0.value.minY < $1.value.minY }.map(\.key)
        let boundary = computeInsertionIndex(locationY: locationY, frames: visibleFrames)

        // Past the last visible card means the end of the list only when there
        // is nothing scrolled below it.
        let insertionIndex: Int
        if boundary < visibleOrder.count,
           let target = remaining.firstIndex(of: visibleOrder[boundary]) {
            insertionIndex = target
        } else if let last = visibleOrder.last,
                  let target = remaining.firstIndex(of: last) {
            insertionIndex = target + 1
        } else {
            insertionIndex = remaining.count
        }

        remaining.insert(movedID, at: max(0, min(insertionIndex, remaining.count)))
        return remaining
    }

    // MARK: - Time Assignment

    /// Encodes order as second-spaced offsets from `base`.
    ///
    /// `spacingSeconds` must stay whole: backups encode dates as ISO-8601 with
    /// whole-second precision, so sub-second offsets would collapse the order
    /// into ties across an export/restore.
    static func assignSequentialTimes(
        ids: [UUID],
        base: Date,
        calendar: Calendar,
        spacingSeconds: Int
    ) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for (idx, id) in ids.enumerated() {
            if let date = calendar.date(byAdding: .second, value: idx * spacingSeconds, to: base) {
                result[id] = date
            }
        }
        return result
    }
}
