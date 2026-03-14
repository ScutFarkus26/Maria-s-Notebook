// ThreePeriodLesson.swift
// Maps existing LessonPresentation states to Montessori three-period lesson terminology.

import SwiftUI

// MARK: - Three-Period Stage

enum ThreePeriodStage: String, CaseIterable, Identifiable {
    case naming
    case recognition
    case recall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .naming: return "Period 1: Naming"
        case .recognition: return "Period 2: Recognition"
        case .recall: return "Period 3: Recall"
        }
    }

    var shortName: String {
        switch self {
        case .naming: return "Naming"
        case .recognition: return "Recognition"
        case .recall: return "Recall"
        }
    }

    var description: String {
        switch self {
        case .naming: return "\"This is...\" — Teacher names the concept for the child"
        case .recognition: return "\"Show me...\" — Child identifies when asked"
        case .recall: return "\"What is...?\" — Child names independently"
        }
    }

    var icon: String {
        switch self {
        case .naming: return "1.circle.fill"
        case .recognition: return "2.circle.fill"
        case .recall: return "3.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .naming: return .blue
        case .recognition: return .orange
        case .recall: return .green
        }
    }

    static func from(state: LessonPresentationState) -> ThreePeriodStage {
        switch state {
        case .presented:
            return .naming
        case .practicing:
            return .recognition
        case .readyForAssessment, .proficient:
            return .recall
        }
    }
}

// MARK: - Three-Period Summary

struct ThreePeriodSummary: Identifiable {
    let id: UUID // LessonPresentation.id
    let studentID: UUID
    let studentName: String
    let lessonID: UUID
    let lessonName: String
    let lessonSubject: String
    let stage: ThreePeriodStage
    let presentedAt: Date
    let lastObservedAt: Date?
    let presentationState: LessonPresentationState
}
