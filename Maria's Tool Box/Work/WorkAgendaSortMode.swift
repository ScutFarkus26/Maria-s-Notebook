import Foundation

public enum WorkAgendaSortMode: String, CaseIterable, Identifiable {
    case lesson = "Lesson"
    case student = "Student"
    case age = "Age"
    case needsAttention = "Needs Attention"
    public var id: String { rawValue }
}
