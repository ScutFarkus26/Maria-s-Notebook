//
//  ChecklistSignposts.swift
//  Cosmic Daybook
//
//  Signpost intervals for the Checklist grid, in the "Checklist" category, so a
//  cell click (tap → matrix updated) shows up as one interval in Instruments
//  next to the Time Profiler. Same shape as `LaunchSignposts`.
//

import OSLog

nonisolated enum ChecklistSignposts {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cosmicdaybook",
        category: "Checklist"
    )

    /// Begins the "Cell action" interval; `action` names which one in the interval's message.
    static func beginCellAction(_ action: String) -> OSSignpostIntervalState {
        signposter.beginInterval("Cell action", id: signposter.makeSignpostID(), "\(action, privacy: .public)")
    }

    static func endCellAction(_ state: OSSignpostIntervalState) {
        signposter.endInterval("Cell action", state)
    }
}
