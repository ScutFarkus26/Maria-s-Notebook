import SwiftUI

// The small warm touches around the grid: the greeting to the assistant, the
// sky behind today's grid, and the picture on a day off (the line when
// everyone's marked is with the grid's rules). Pure, so the tests call them
// directly.

/// "Good morning, Rivka · Day 37": to the assistant, by the first word of the
/// name she gave (`ClassroomIdentity.displayName`), or without a name when she
/// hasn't. The first day and the hundredth get their own words.
enum AssistantGreeting {
    static func text(at date: Date, name: String?, dayNumber: Int? = nil, calendar: Calendar = .current) -> String {
        let first = firstName(name)
        switch AssistantSchoolDayCount.milestone(for: dayNumber) {
        case .firstDay:
            return first.map { "Welcome to a new year, \($0)" } ?? "Welcome to a new year"
        case .hundredthDay:
            return first.map { "Happy 100th day, \($0)!" } ?? "Happy 100th day!"
        case nil:
            let hour = calendar.component(.hour, from: date)
            let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
            let greeting = first.map { "\(part), \($0)" } ?? part
            return dayNumber.map { "\(greeting) · Day \($0)" } ?? greeting
        }
    }

    /// The first word of her name, or nil when there's none.
    static func firstName(_ name: String?) -> String? {
        guard let word = name?.trimmed().split(separator: " ").first else { return nil }
        return String(word)
    }
}

/// The color of the sky at an hour of the school day, washed faintly over the
/// top of today's grid: dawn pink, sunrise gold, morning and midday blue,
/// afternoon gold, dusk violet, blended between.
enum AssistantSky {
    struct Tint: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }

        func mixed(with other: Tint, by amount: Double) -> Tint {
            Tint(
                red: red + (other.red - red) * amount,
                green: green + (other.green - green) * amount,
                blue: blue + (other.blue - blue) * amount
            )
        }
    }

    static let dawn = Tint(red: 1.0, green: 0.72, blue: 0.68)
    static let sunrise = Tint(red: 1.0, green: 0.84, blue: 0.52)
    static let morning = Tint(red: 0.56, green: 0.78, blue: 1.0)
    static let midday = Tint(red: 0.45, green: 0.70, blue: 1.0)
    static let afternoon = Tint(red: 1.0, green: 0.78, blue: 0.50)
    static let dusk = Tint(red: 0.62, green: 0.52, blue: 0.92)

    /// Hours of the day and their sky; before the first and after the last
    /// the sky holds.
    private static let anchors: [(hour: Double, tint: Tint)] = [
        (5.5, dawn), (7.5, sunrise), (10, morning), (13, midday), (16, afternoon), (19, dusk)
    ]

    static func tint(at date: Date, calendar: Calendar = .current) -> Tint {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        guard let first = anchors.first, let last = anchors.last else { return morning }
        if hour <= first.hour { return first.tint }
        if hour >= last.hour { return last.tint }
        for (earlier, later) in zip(anchors, anchors.dropFirst()) where hour < later.hour {
            return earlier.tint.mixed(with: later.tint, by: (hour - earlier.hour) / (later.hour - earlier.hour))
        }
        return last.tint
    }
}

/// The picture and words for a day with no school.
struct AssistantDayOffArt: Equatable {
    let symbol: String
    let color: Color
    let title: String

    static func art(for dayOff: AssistantAttendanceViewModel.DayOff) -> AssistantDayOffArt {
        switch dayOff {
        case .weekend:
            return AssistantDayOffArt(symbol: "sun.max.fill", color: .orange, title: "Weekend")
        case .holiday(let reason):
            let (symbol, color) = picture(for: reason ?? "")
            return AssistantDayOffArt(symbol: symbol, color: color, title: reason ?? "Day Off")
        }
    }

    /// A picture for the words in a day off's reason: the school's holidays
    /// and breaks by season, days for the teachers, and a party otherwise.
    private static func picture(for reason: String) -> (String, Color) {
        let words = reason.lowercased()
        func mentions(_ keys: [String]) -> Bool { keys.contains { words.contains($0) } }
        if mentions(["winter", "christmas", "hanukkah", "chanukah", "snow", "new year"]) {
            return ("snowflake", .cyan)
        }
        if mentions(["thanksgiving", "sukkot", "succot", "fall", "autumn"]) {
            return ("leaf.fill", .orange)
        }
        if mentions(["spring", "passover", "pesach", "easter"]) {
            return ("camera.macro", .pink)
        }
        if mentions(["summer"]) {
            return ("sun.horizon.fill", .orange)
        }
        if mentions(["conference", "teacher", "workday", "work day", "professional", "in-service", "planning"]) {
            return ("books.vertical.fill", .indigo)
        }
        return ("party.popper.fill", .purple)
    }

    /// The line under the title: to the assistant on today, about the day
    /// otherwise.
    static func message(
        for dayOff: AssistantAttendanceViewModel.DayOff,
        isToday: Bool,
        name: String?
    ) -> String {
        let first = AssistantGreeting.firstName(name).map { ", \($0)" } ?? ""
        switch (dayOff, isToday) {
        case (.weekend, true):
            return "Enjoy the weekend\(first). Attendance opens again on the next school day."
        case (.holiday, true):
            return "Enjoy the day off\(first). No attendance is taken today."
        case (.weekend, false):
            return "No school that day. Use the arrows to move between school days."
        case (.holiday, false):
            return "A day off on your guide's school calendar. No attendance is taken."
        }
    }
}
