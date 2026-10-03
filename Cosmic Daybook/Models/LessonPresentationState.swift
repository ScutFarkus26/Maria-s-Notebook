import Foundation

enum LessonPresentationState: String, Codable, CaseIterable, Sendable {
    case presented
    case practicing
    case readyForAssessment
    case proficient = "mastered"
}
