import Foundation
import SwiftData

@Model final class WorkNote: Identifiable {
    // Core fields
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date()
    var text: String = ""
    var isLessonToGive: Bool = false
    var isPinned: Bool = false

    // Relationships
    // Main attachment to Work. Inverse is WorkModel.checkNotes with cascade delete from Work side.
    @Relationship var work: WorkModel?

    // Optional convenience relationships
    @Relationship var student: Student?
    @Relationship var lesson: Lesson?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        text: String = "",
        isLessonToGive: Bool = false,
        isPinned: Bool = false,
        work: WorkModel? = nil,
        student: Student? = nil,
        lesson: Lesson? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.isLessonToGive = isLessonToGive
        self.isPinned = isPinned
        self.work = work
        self.student = student
        self.lesson = lesson
    }
}

/*
Sanity checklist:
 • Add note works
 • Lesson to give appears in Planning
 • Clear removes from Planning but keeps note attached to work
 • Delete note works and cascades appropriately
*/

