// ThreeYearCycleTypes.swift
// Value types for the Three-Year Cycle Bird's-Eye View feature.

import SwiftUI

// MARK: - Cycle Year

enum CycleYear: Int, CaseIterable, Identifiable, Sendable {
    case unknown = 0
    case first = 1
    case second = 2
    case third = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .first: return "Year 1"
        case .second: return "Year 2"
        case .third: return "Year 3"
        }
    }

    var shortName: String {
        switch self {
        case .unknown: return "?"
        case .first: return "Y1"
        case .second: return "Y2"
        case .third: return "Y3"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .first: return .blue
        case .second: return .purple
        case .third: return .orange
        }
    }

    /// Calculate year-in-cycle from a student's start date.
    static func calculate(from dateStarted: Date?) -> CycleYear {
        guard let start = dateStarted else { return .unknown }
        let seconds = Date().timeIntervalSince(start)
        guard seconds > 0 else { return .first }
        let years = floor(seconds / (365.25 * 86400)) + 1
        let clamped = max(1, min(3, Int(years)))
        return CycleYear(rawValue: clamped) ?? .unknown
    }

    /// Selectable year options (excludes unknown).
    static var selectableCases: [CycleYear] { [.first, .second, .third] }
}

// MARK: - Pace Indicator

enum PaceIndicator: String, Sendable {
    case ahead
    case onTrack
    case behind
    case farBehind

    var displayName: String {
        switch self {
        case .ahead: return "Ahead"
        case .onTrack: return "On Track"
        case .behind: return "Behind"
        case .farBehind: return "Needs Attention"
        }
    }

    var color: Color {
        switch self {
        case .ahead: return AppColors.success
        case .onTrack: return .blue
        case .behind: return AppColors.warning
        case .farBehind: return AppColors.destructive
        }
    }

    var icon: String {
        switch self {
        case .ahead: return "hare"
        case .onTrack: return SFSymbol.Action.checkmarkCircleFill
        case .behind: return "tortoise"
        case .farBehind: return "exclamationmark.triangle.fill"
        }
    }

    /// Calculate pace based on actual coverage vs expected for current year.
    static func calculate(coveragePercentage: Double, cycleYear: CycleYear) -> PaceIndicator {
        guard cycleYear != .unknown else { return .onTrack }
        let expectedPercentage = Double(cycleYear.rawValue) / 3.0
        guard expectedPercentage > 0 else { return .onTrack }
        let ratio = coveragePercentage / expectedPercentage
        switch ratio {
        case 1.1...: return .ahead
        case 0.8..<1.1: return .onTrack
        case 0.5..<0.8: return .behind
        default: return .farBehind
        }
    }
}

// MARK: - Student Cycle Card

struct CycleStudentCard: Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let nickname: String?
    let level: CDStudent.Level
    let cycleYear: CycleYear
    let dateStarted: Date?
    let totalLessonsPresented: Int
    let totalLessonsAvailable: Int
    let coveragePercentage: Double
    let subjectCoverage: [SubjectCoverage]
    let paceIndicator: PaceIndicator

    var displayName: String { nickname ?? firstName }

    var initials: String {
        let first = firstName.prefix(1)
        let last = lastName.prefix(1)
        return "\(first)\(last)".uppercased()
    }
}

// MARK: - Subject Coverage

struct SubjectCoverage: Identifiable, Sendable {
    let id: String
    let subject: String
    let presented: Int
    let total: Int
    let percentage: Double
    let color: Color
}

// MARK: - Sort Order

enum CycleSortOrder: String, CaseIterable, Identifiable, Sendable {
    case name
    case pace
    case coverage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return "Name"
        case .pace: return "Pace"
        case .coverage: return "Coverage"
        }
    }
}
