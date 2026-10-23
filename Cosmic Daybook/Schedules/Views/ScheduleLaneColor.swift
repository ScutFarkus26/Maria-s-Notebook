// ScheduleLaneColor.swift
// A lane's color on the Schedules page and Today. `CDTimetableLane.colorRaw`
// holds one of these names; empty means the page picks by the lane's place.

import SwiftUI

enum ScheduleLaneColor: String, CaseIterable, Identifiable {
    case blue
    case orange
    case green
    case purple
    case teal
    case pink
    case indigo
    case brown

    var id: String { rawValue }

    /// "Blue", for the Lanes sheet's menu.
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var color: Color {
        switch self {
        case .blue: .blue
        case .orange: .orange
        case .green: .green
        case .purple: .purple
        case .teal: .teal
        case .pink: .pink
        case .indigo: .indigo
        case .brown: .brown
        }
    }

    /// The lane's own color, or the one its place in the order gives it.
    static func of(_ lane: TimetableLaneSnapshot) -> ScheduleLaneColor {
        if let chosen = ScheduleLaneColor(rawValue: lane.colorRaw) { return chosen }
        let all = allCases
        return all[((lane.sortOrder % all.count) + all.count) % all.count]
    }

    static func color(of lane: TimetableLaneSnapshot) -> Color { of(lane).color }
}
