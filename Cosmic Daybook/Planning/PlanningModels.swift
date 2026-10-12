import SwiftUI
import CoreData
import Foundation

enum DayPeriod: CaseIterable, Hashable, Sendable {
    case morning, afternoon

    public var label: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        }
    }

    public var baseHour: Int {
        switch self {
        case .morning: return UIConstants.morningHour
        case .afternoon: return UIConstants.afternoonHour
        }
    }
}
