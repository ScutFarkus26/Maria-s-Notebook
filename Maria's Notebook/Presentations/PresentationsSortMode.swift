import Foundation

public enum PresentationsSortMode: String, CaseIterable, Identifiable, Sendable {
    case lesson = "Lesson"
    case student = "Student"
    case age = "Age"
    case needsAttention = "Needs Attention"
    public var id: String { rawValue }
}
