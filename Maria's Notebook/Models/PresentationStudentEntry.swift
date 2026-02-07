import Foundation

/// Model for per-student data during post-presentation form entry.
/// Ephemeral model used only during form editing, not persisted to SwiftData.
struct PresentationStudentEntry: Identifiable {
    let id: UUID // student ID
    let name: String
    var understandingLevel: Int = 3 // 1-5 scale
    var observation: String = ""
    var assignment: String = ""
    var checkInDate: Date?
    var dueDate: Date?

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
