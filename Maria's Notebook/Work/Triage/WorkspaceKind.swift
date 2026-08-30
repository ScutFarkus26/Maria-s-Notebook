// WorkspaceKind.swift
// The Lessons & Work workspace's top-level axis: which *kind* of record the
// guide is working on.
//
// The workspace used to split by state first — Attention over To Schedule —
// and then split by kind one level down: To Schedule carried its own
// Presentations / Work picker, and Attention carried "Observe or Decide" and
// "Check Work" sections. Kind was therefore already the real organising axis,
// applied twice, a level too low. Moving between "work I have to check" and
// "work I have to plan" cost two pickers, and the Attention count mixed both
// kinds, so the number never said what sort of action was waiting.
//
// Kind is now the top level, and state is the pill row inside it —
// `PresentationsFilterChip` on one side, `WorkFilterChip` on the other. The
// state buckets themselves did not change: `LessonsAndWorkTriage` still places
// every record in exactly one `TriageBucket`, and `WorkFilterChip` is a thin
// naming layer over those same values.

import Foundation

/// The two halves of the workspace. Not a `TriageBucket` — kind and state are
/// orthogonal, and every kind carries the full set of states.
enum WorkspaceKind: String, CaseIterable, Identifiable, Sendable {
    /// Lessons to give: what is ready, what is brewing, what needs following.
    case presentations
    /// Children's work: what needs checking, what needs a day.
    case work

    var id: Self { self }

    var title: String {
        switch self {
        case .presentations: "Presentations"
        case .work: "Work"
        }
    }

    var systemImage: String {
        switch self {
        case .presentations: "tray.full"
        case .work: "square.and.pencil"
        }
    }

    var searchPrompt: String {
        switch self {
        case .presentations: "Search children or lessons"
        case .work: "Search children, lessons, or work"
        }
    }

    /// Resolves a saved selection, including a value left behind by a build
    /// whose picker still held `TriageBucket` raw values.
    static func resolved(rawValue: String?) -> Self {
        guard let rawValue else { return .presentations }
        if let kind = Self(rawValue: rawValue) { return kind }
        // A workspace saved under the old state-first picker: "attention" was
        // mostly work to check, and "toSchedule" opened on presentations.
        switch TriageBucket(rawValue: rawValue) {
        case .attention: return .work
        default: return .presentations
        }
    }

    /// Which half holds a record of this kind. Deep links resolve through here
    /// so a route naming a record always lands on the list that contains it.
    static func holding(presentationID: UUID?, workID: UUID?) -> Self {
        workID != nil ? .work : .presentations
    }
}
