// WorkspaceList.swift
// Which list each half of the Lessons & Work workspace is showing: what is
// still to do, or its history.
//
// The workspace holds only open records; finished ones fall out to
// `TriageBucket.done`. Their lists (every presentation given, every piece of
// work finished) used to live under Logs, a screen of their own that only
// repeated this one, so each half now carries a History choice instead (plan
// "Simplify the app", Phase 2). Each half remembers its own choice: History
// on the Work side doesn't turn the Presentations side to history too.

import Foundation

enum WorkspaceList: String, CaseIterable, Identifiable, Sendable {
    /// The half's live list: lessons to give, or work still open.
    case open
    /// What's finished: presentations given, or work finished.
    case history

    var id: Self { self }

    /// The choice's name in a half: the live list is "Upcoming" on the
    /// Presentations side (what the pane has always been) and "Open" on the
    /// Work side (its empty state's word); both have "History".
    func title(in kind: WorkspaceKind) -> String {
        switch (self, kind) {
        case (.open, .presentations): "Upcoming"
        case (.open, .work), (.open, .reports): "Open"
        case (.history, _): "History"
        }
    }

    /// The search field's prompt in a half. History searches what its list
    /// can match: a presentation's lesson, or a work item's title and notes.
    func searchPrompt(in kind: WorkspaceKind) -> String {
        switch (self, kind) {
        case (.open, _): kind.searchPrompt
        case (.history, .presentations): "Search lessons given"
        case (.history, .work), (.history, .reports): "Search finished work"
        }
    }

    /// The list a route lands on. Only a finished record (`.done`) is in
    /// History; every other bucket is one of the live list's.
    static func holding(_ bucket: TriageBucket) -> Self {
        bucket == .done ? .history : .open
    }

    /// Resolves a saved choice, falling back to the live list.
    static func resolved(rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .open
    }
}
