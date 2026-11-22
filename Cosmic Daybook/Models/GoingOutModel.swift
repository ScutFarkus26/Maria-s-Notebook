import Foundation
import SwiftUI

// MARK: - Status Enums

enum GoingOutStatus: String, CaseIterable, Identifiable, Codable {
    case proposed
    case planning
    case approved
    case completed
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .proposed: return "Proposed"
        case .planning: return "Planning"
        case .approved: return "Approved"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var icon: String {
        switch self {
        case .proposed: return "lightbulb"
        case .planning: return "list.clipboard"
        case .approved: return "checkmark.seal"
        case .completed: return "flag.checkered"
        case .cancelled: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .proposed: return .blue
        case .planning: return .orange
        case .approved: return .green
        case .completed: return .purple
        case .cancelled: return .gray
        }
    }
}

enum PermissionStatus: String, CaseIterable, Identifiable, Codable {
    case pending
    case sent
    case approved
    case denied

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .sent: return "Sent"
        case .approved: return "Approved"
        case .denied: return "Denied"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .sent: return "envelope"
        case .approved: return "checkmark.circle"
        case .denied: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .sent: return .blue
        case .approved: return .green
        case .denied: return .red
        }
    }
}
