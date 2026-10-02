//
//  ChecklistLens.swift
//  Cosmic Daybook
//
//  How the checklist grid reads: every mark, or "Ready to Present", which lifts the
//  cells a child could be given now (not presented, not planned, nothing before the
//  lesson holding her back — the cell's Ready mark) and fades the rest. Display only:
//  a lens never changes a record, and the grid opens on All Marks each time.
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
        case .allMarks: return "All Marks"
        case .ready: return "Ready to Present (\(readyCount))"
        }
    }

    /// The status bar's line while the Ready lens is on: the rule a ringed cell meets.
    static let readyRule = "Ringed: not presented or planned, and nothing holds it back"

    /// How faint every mark that isn't Ready draws under the Ready lens.
    static let fadedOpacity: Double = 0.2
}
