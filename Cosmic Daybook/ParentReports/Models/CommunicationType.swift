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
}
