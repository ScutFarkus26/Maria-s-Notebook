import SwiftUI
import Foundation

enum DayPeriod: CaseIterable, Hashable, Sendable {
    case morning, afternoon

    public var label: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        }
    }

    public var color: Color {
        switch self {
        case .morning: return .blue
        case .afternoon: return .orange
        }
    }

    public var baseHour: Int {
        switch self {
        case .morning: return UIConstants.morningHour
        case .afternoon: return UIConstants.afternoonHour
        }
    }
}

struct DayKey: Hashable {
    let dayStart: Date
    let period: DayPeriod

    init(dayStart: Date, period: DayPeriod) {
        self.dayStart = dayStart
        self.period = period
    }
}

struct ScheduledItem: Identifiable, Hashable {
    let work: WorkModel
    let checkIn: WorkCheckIn
    var id: UUID { checkIn.id }

    init(work: WorkModel, checkIn: WorkCheckIn) {
        self.work = work
        self.checkIn = checkIn
    }
}
