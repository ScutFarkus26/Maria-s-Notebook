// MeetingsScreenView.swift
// The Meetings screen's two views: the queue of children to meet, and the
// history of every meeting. The history was the Meetings log under Logs, a
// screen that only repeated this one (plan "Simplify the app", Phase 2).

import Foundation

enum MeetingsScreenView: String, CaseIterable, Identifiable, Sendable {
    /// Who to meet next, beside the meeting itself.
    case queue
    /// Every child's meetings by day (`MeetingsLogView`).
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .queue: "Queue"
        case .history: "History"
        }
    }

    /// Resolves a saved view, falling back to the queue.
    static func resolved(rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .queue
    }
}
