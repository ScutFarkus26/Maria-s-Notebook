// PrepScheduleType.swift
// Enum for prep checklist schedule frequency.

import SwiftUI

enum PrepScheduleType: String, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .daily: return "sun.max"
        case .weekly: return "calendar.badge.clock"
        case .custom: return "slider.horizontal.3"
        }
    }
}
