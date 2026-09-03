// WorkFilterChip.swift
// The Work half's filter pills.
//
// These are `TriageBucket` wearing the workspace's vocabulary. The rule that
// decides where a work item belongs did not move or change — `.needsChecking`
// *is* `.attention`, `.toSchedule` is `.toSchedule`, `.scheduled` is
// `.scheduled` — so a pill can never disagree with the badge on the card it
// reveals. What changed is only where the guide picks between them: these used
// to be the workspace's own top-level tabs, and are now a pill row inside the
// Work half, matching the row Presentations already had.
//
// `.all` has no bucket. It is the old "All Open Work" toolbar toggle, which
// was a second way of saying the same thing from a different control.

import SwiftUI

nonisolated enum WorkFilterChip: String, CaseIterable, Identifiable, Sendable, WorkspaceFilterChip {
    /// Every open work item, whatever state it is in.
    case all
    /// Waiting on the guide: due, overdue, in review, or gone quiet.
    case needsChecking
    /// Real and open, but carrying no date at all.
    case toSchedule
    /// Has a day on it and that day has not arrived.
    case scheduled

    var id: Self { self }

    /// The bucket this pill shows, or `nil` for the unfiltered pill.
    var bucket: TriageBucket? {
        switch self {
        case .all: nil
        case .needsChecking: .attention
        case .toSchedule: .toSchedule
        case .scheduled: .scheduled
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .needsChecking: "Needs Checking"
        case .toSchedule: "To Schedule"
        case .scheduled: "Scheduled"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .needsChecking: "exclamationmark.circle"
        case .toSchedule: "tray.and.arrow.down"
        case .scheduled: "calendar"
        }
    }

    var accent: Color {
        switch self {
        case .all: .secondary
        case .needsChecking: AppColors.color(for: .overdue)
        case .toSchedule: AppColors.attention
        case .scheduled: .accentColor
        }
    }

    /// The records this pill shows, out of an already-triaged screenful.
    ///
    /// Generic and Core Data-free for the same reason `TriageSplit` is: the
    /// guarantee worth testing is that the pills cover every workspace bucket
    /// and overlap only where `.all` deliberately does.
    func slice<Record>(of split: TriageSplit<Record>) -> [Record] {
        if let bucket { return split[bucket] }
        // `.all` is every open record — the three workspace buckets. `.done`
        // is history and lives under Logs.
        return split.attention + split.scheduled + split.toSchedule
    }

    /// The pill that shows a given bucket. `.done` is history and has no pill,
    /// so it falls back to the unfiltered one rather than selecting a list that
    /// cannot hold the record.
    static func showing(_ bucket: TriageBucket) -> Self {
        allCases.first { $0.bucket == bucket } ?? .all
    }

    /// Resolves a saved selection, falling back to the unfiltered pill.
    static func resolved(rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .all
    }
}
