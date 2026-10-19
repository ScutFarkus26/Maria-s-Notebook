//
//  ChecklistLens.swift
//  Cosmic Daybook
//
//  How the checklist grid reads: every mark, or "Ready to Present", which lifts the
//  cells a child could be given now (not presented, not planned, and the lesson before
//  confirmed or mastered — the cell's Ready mark, by the one readiness rule
//  `ReadyForNextEngine.readiness(of:)`; a Ready, check first cell is lifted too, and its
//  hover and card say what to check) and fades the rest. Display only: a lens never
//  changes a record, and the grid opens on All Marks each time.
//

import Foundation

enum ChecklistLens: String, CaseIterable, Identifiable {
    case allMarks
    case ready

    var id: String { rawValue }

    /// The toolbar's segment, or the iPhone menu's item; the Ready one carries the
    /// count over the rows and children on screen.
    func title(readyCount: Int) -> String {
        switch self {
        case .allMarks: return "All marks"
        case .ready: return "Ready \(readyCount)"
        }
    }

    /// The status bar's line while the Ready lens is on: what the two colors mean.
    static let readyRule = "Blue: ready · Amber: ready, check first (the card says why)"

    /// How faint every mark that isn't Ready draws under the Ready lens.
    static let fadedOpacity: Double = 0.2
}
