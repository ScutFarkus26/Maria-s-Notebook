// CommunicationType.swift
// Enum for parent communication categories.

import SwiftUI

enum CommunicationType: String, CaseIterable, Identifiable, Sendable {
    case conference
    case progressUpdate
    case monthlyReport
    case concern
    case introduction
    case endOfYear
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conference: return "Conference"
        case .progressUpdate: return "Progress Update"
        case .monthlyReport: return "Monthly Report"
        case .concern: return "Concern"
        case .introduction: return "Introduction"
        case .endOfYear: return "End of Year"
        case .custom: return "Custom"
        }
    }

    var color: Color {
        switch self {
        case .conference: return .blue
        case .progressUpdate: return AppColors.success
        case .monthlyReport: return .teal
        case .concern: return AppColors.warning
        case .introduction: return .purple
        case .endOfYear: return .orange
        case .custom: return .secondary
        }
    }
}
