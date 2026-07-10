// PresentationsCompactView.swift
// Tab enum for the compact (iPhone-class) layout of the Presentations planner.
// The 3-tab layout itself is rendered inline in `PresentationsView+Body.compactLayout`
// because it needs direct access to `viewModel`, `coordinator`, drag callbacks,
// and the `WeekPlanSection` constructor.

import Foundation

enum PresentationsCompactTab: String, CaseIterable, Identifiable, Sendable {
    case ready
    case week
    case students

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: return "Ready"
        case .week: return "Week"
        case .students: return "Students"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "tray.full"
        case .week: return "calendar"
        case .students: return "person.2"
        }
    }
}
