// LessonFrequencyTypes.swift
// Value types for the CDLesson Frequency Dashboard.
// Tracks per-student weekly lesson counts relative to the AMI target of 5–7 lessons/week.

import Foundation
import SwiftUI

/// Per-student weekly lesson count card.
struct StudentFrequencyCard: Identifiable {
    let id: UUID                  // student.id
    let firstName: String
    let lastName: String
    let nickname: String?
    let level: CDStudent.Level
    let lessonCount: Int          // total lessons this week
    let subjectBreakdown: [SubjectCount]  // sorted by count descending

    var displayName: String { nickname ?? firstName }
}

/// Count of lessons in a single subject for a student in a given week.
struct SubjectCount: Identifiable {
    var id: String { subject }
    let subject: String
    let count: Int
}

/// Status relative to the AMI target range (default 5–7 lessons/week).
enum FrequencyStatus {
    case belowTarget   // < lower bound (red)
    case onTarget      // within range (green)
    case aboveTarget   // > upper bound (blue/neutral)

    static func from(count: Int, target: ClosedRange<Int>) -> FrequencyStatus {
        if count < target.lowerBound { return .belowTarget }
        if count > target.upperBound { return .aboveTarget }
        return .onTarget
    }

    var color: Color {
        switch self {
        case .belowTarget: return AppColors.destructive
        case .onTarget: return AppColors.success
        case .aboveTarget: return AppColors.info
        }
    }

    var icon: String {
        switch self {
        case .belowTarget: return "exclamationmark.triangle.fill"
        case .onTarget: return "checkmark.circle.fill"
        case .aboveTarget: return "arrow.up.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .belowTarget: return "Below Target"
        case .onTarget: return "On Target"
        case .aboveTarget: return "Above Target"
        }
    }
}
