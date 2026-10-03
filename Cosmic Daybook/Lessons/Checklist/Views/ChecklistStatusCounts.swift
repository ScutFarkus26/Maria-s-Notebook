//
//  ChecklistStatusCounts.swift
//  Cosmic Daybook
//
//  How many cells sit on each rung of the ladder, over the rows and columns the
//  grid is showing. The status bar's legend reads it; the view model recomputes
//  it when the matrix or a filter changes, never per body evaluation.
//

import Foundation

struct ChecklistStatusCounts: Equatable {
    private(set) var byStatus: [ChecklistDisplayStatus: Int] = [:]
    /// Cells whose open work asks for a check-in (they count on their rung too).
    private(set) var needsCheckIn: Int = 0
    /// Cells counted: visible students × visible lessons that have a state.
    private(set) var total: Int = 0

    init() {}

    /// Counts `matrix` (student → lesson → state) over the given students and lessons only.
    init(matrix: ChecklistMatrixBuilder.Matrix, studentIDs: [UUID], lessonIDs: [UUID]) {
        for studentID in studentIDs {
            guard let row = matrix[studentID] else { continue }
            for lessonID in lessonIDs {
                guard let state = row[lessonID] else { continue }
                byStatus[state.displayStatus, default: 0] += 1
                if state.needsCheckIn { needsCheckIn += 1 }
                total += 1
            }
        }
    }

    subscript(status: ChecklistDisplayStatus) -> Int {
        byStatus[status] ?? 0
    }
}
