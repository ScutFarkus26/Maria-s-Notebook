//
//  SiriAttendanceChange.swift
//  Cosmic Daybook
//
//  The last attendance change Siri made, kept on this device so "Undo that"
//  can put it back even after the app has been suspended in between.
//
//  Shared with Daybook Assistant, which compiles this file by path.
//

import Foundation

nonisolated struct SiriAttendanceChange: Codable, Sendable {
    struct Mark: Codable, Sendable {
        /// The record's object URI: records are per store, like the key.
        let recordURI: URL
        let from: AttendanceStatus
        let to: AttendanceStatus
        /// The stored absence reason before and after, when the change set
        /// one: "Mark Maya absent, sick" on a child already absent changes
        /// only this. Nil on changes remembered before 2026-09-29.
        var fromReasonRaw: String?
        var toReasonRaw: String?
    }

    let day: Date
    let marks: [Mark]
    /// "Maya Stone present", for the undo's answer.
    let summary: String
    /// Closing arrival also switched the Daybook Assistant to Late.
    let closedArrival: Bool

    /// Object URIs name one store, so the key is per CloudKit environment.
    @MainActor private static var key: String {
        CloudKitEnvironment.scoped("Siri.lastAttendanceChange")
    }

    @MainActor func remember(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    @MainActor static func last(defaults: UserDefaults = .standard) -> SiriAttendanceChange? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SiriAttendanceChange.self, from: data)
    }

    @MainActor static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// Closing arrival on `day` forgets Siri's last change that day: it came
    /// before, so "Undo that" would put back an older voice mark, not the
    /// Close Arrival. A change on another day is kept.
    @MainActor static func forget(ifOn day: Date, defaults: UserDefaults = .standard) {
        guard let change = last(defaults: defaults),
              Calendar.current.isDate(change.day, inSameDayAs: day) else { return }
        forget(defaults: defaults)
    }
}
