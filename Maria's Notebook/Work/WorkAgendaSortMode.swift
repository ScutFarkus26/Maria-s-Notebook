import Foundation

public enum WorkAgendaSortMode: String, CaseIterable, Identifiable {
    case student = "Student"
    case lesson = "Lesson"
    case age = "Age"
    case needsAttention = "Needs Attention"
    public var id: String { rawValue }
}
