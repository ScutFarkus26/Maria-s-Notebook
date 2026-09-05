//
//  LaunchSignposts.swift
//  Maria's Notebook
//
//  One OSSignposter for the cold-launch path so the bootstrap phases show up
//  as intervals in Instruments (App Launch / Time Profiler → "Launch" category)
//  alongside the existing `Bootstrap:` log lines. Interval names are stable
//  strings; compare them against Documentation/Implementation/perf-baselines/.
//

import OSLog

nonisolated enum LaunchSignposts {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook",
        category: "Launch"
    )

    /// Begins a named launch interval. Pass the returned state to `end`.
    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// A point-in-time marker, e.g. the moment the UI is allowed to render.
    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
