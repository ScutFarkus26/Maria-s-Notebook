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

    @MainActor func remember() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    @MainActor static func last() -> SiriAttendanceChange? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SiriAttendanceChange.self, from: data)
    }

    @MainActor static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
