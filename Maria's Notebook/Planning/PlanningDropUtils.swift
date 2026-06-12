// PlanningDropUtils.swift
// Utilities for computing insertion indices and assigning times for drag/drop in planning views.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import CoreGraphics

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

    // MARK: - Time Assignment
    @MainActor static func assignSequentialTimes(
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
