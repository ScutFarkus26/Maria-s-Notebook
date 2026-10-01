import Foundation

/// When the guide wants to see the children's work again.
///
/// `nextWorkCycle` keeps the work visible in Children Working without inventing
/// a deadline; `on` schedules a check-in on that day.
nonisolated enum PresentationCheckIn: Equatable, Hashable, Codable, Sendable {
    case nextWorkCycle
    case on(Date)

    /// The day, at its start, or nil for the next work cycle.
    var day: Date? {
        switch self {
        case .nextWorkCycle: nil
        case .on(let date): AppCalendar.startOfDay(date)
        }
    }

    init(day: Date?) {
        if let day {
            self = .on(AppCalendar.startOfDay(day))
        } else {
            self = .nextWorkCycle
        }
    }
}
