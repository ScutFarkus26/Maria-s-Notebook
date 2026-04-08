// CommunicationType.swift
// Enum for parent communication categories.

import SwiftUI

enum CommunicationType: String, CaseIterable, Identifiable, Sendable {
    case conference
    case progressUpdate
    case concern
    case introduction
    case endOfYear
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conference: return "Conference"
        case .progressUpdate: return "Progress Update"
        case .concern: return "Concern"
        case .introduction: return "Introduction"
        case .endOfYear: return "End of Year"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .conference: return "person.2"
        case .progressUpdate: return "chart.line.uptrend.xyaxis"
        case .concern: return "exclamationmark.bubble"
        case .introduction: return "hand.wave"
        case .endOfYear: return "gift"
        case .custom: return "square.and.pencil"
        }
    }

    var color: Color {
        switch self {
        case .conference: return .blue
        case .progressUpdate: return AppColors.success
        case .concern: return AppColors.warning
        case .introduction: return .purple
        case .endOfYear: return .orange
        case .custom: return .secondary
        }
    }
}

enum CommunicationTab: String, CaseIterable, Identifiable, Sendable {
    case drafts
    case sent
    case templates

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .drafts: return "Drafts"
        case .sent: return "Sent"
        case .templates: return "Templates"
        }
    }
}
