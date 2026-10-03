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
        /// The whole record before and after the change, so Undo puts back
        /// its times too, as ⌘Z does: a late arrival who had left early
        /// comes back with her arrival, departure and the mark she left
        /// from. Nil on changes remembered before 2026-10-03, and on Close
        /// Arrival's marks.
        var before: AttendanceRecordSnapshot.Values?
        var after: AttendanceRecordSnapshot.Values?
    }

    let day: Date
    let marks: [Mark]
    /// "Maya Stone present", for the log.
    let summary: String
    /// Closing arrival also switched the Daybook Assistant to Late.
    let closedArrival: Bool
    /// The child's name as Siri said it ("Maya Stone"), for a one-child
    /// change. Nil for Close Arrival and on changes remembered before
    /// 2026-10-03.
    var name: String?

    /// What Siri says once this change is undone: "Done. Maya Stone isn't
    /// marked present anymore."
    var undoneDialog: String {
        if closedArrival { return "Done. Arrival is open again." }
        guard let name, marks.count == 1, let mark = marks.first else { return "Done. I put that back." }
        if mark.from == mark.to { return "Done. \(name)'s absence reason is back the way it was." }
        return "Done. \(name) isn't marked \(mark.to.spokenWord) anymore."
    }

    /// What Siri says when someone has changed these marks since, so Undo
    /// left them: "Maya Stone's mark has changed since then, so I left it alone."
    var changedSinceDialog: String {
        if let name, marks.count == 1 { return "\(name)'s mark has changed since then, so I left it alone." }
        if closedArrival {
            return "Those absent marks have changed since then, so I left them alone. Arrival is open again."
        }
        return "Those marks have changed since then, so I left them alone."
    }

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
