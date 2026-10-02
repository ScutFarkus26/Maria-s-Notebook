//
//  ChecklistRowSummary.swift
//  Cosmic Daybook
//
//  One lesson across the children on screen, for the Class column: how many have
//  mastered it, are somewhere between presented and mastered, or have it planned.
//  "17/22" counts the children who have had the lesson (mastered or in progress).
//

import Foundation

struct ChecklistRowSummary: Equatable {
    private(set) var mastered = 0
    /// Presented, practicing or reviewing.
    private(set) var inProgress = 0
    private(set) var planned = 0
    /// Ready for it now: the Ready lens's "5 ready".
    private(set) var ready = 0
    /// Every child counted, whatever their rung.
    private(set) var total = 0

    /// Children who have had the lesson: the "17" in "17/22".
    var given: Int { mastered + inProgress }

    init() {}

    init(statuses: some Sequence<ChecklistDisplayStatus>) {
        for status in statuses {
            total += 1
            switch status {
            case .mastered: mastered += 1
            case .presented, .practicing, .reviewing: inProgress += 1
            case .planned: planned += 1
            case .ready: ready += 1
            case .notReady: break
            }
        }
    }

    /// One summary per lesson over the given students. A child with no state for the
    /// lesson counts as Ready, as the cell draws it.
    static func summaries(
        matrix: ChecklistMatrixBuilder.Matrix,
        studentIDs: [UUID],
        lessonIDs: [UUID]
    ) -> [UUID: ChecklistRowSummary] {
        var result: [UUID: ChecklistRowSummary] = [:]
        result.reserveCapacity(lessonIDs.count)
        let rows = studentIDs.map { matrix[$0] }
        for lessonID in lessonIDs {
            result[lessonID] = ChecklistRowSummary(
                statuses: rows.lazy.map { $0?[lessonID]?.displayStatus ?? .ready }
            )
        }
        return result
    }

    /// "17 of 22 have had it · 9 mastered · 2 planned".
    var helpText: String {
        var parts = ["\(given) of \(total) have had it"]
        if mastered > 0 { parts.append("\(mastered) mastered") }
        if planned > 0 { parts.append("\(planned) planned") }
        return parts.joined(separator: " · ")
    }
}
