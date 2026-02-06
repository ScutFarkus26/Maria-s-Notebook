import Foundation
import SwiftData

/// Note attached to Student-related entities (Student, StudentMeeting, StudentLesson).
///
/// **Type Safety:** Single required relationship to Student
/// **Optional Links:** Can link to StudentMeeting or StudentLesson for specific context
/// **Use Cases:**
/// - General student observations
/// - Student meeting notes
/// - Student lesson observations
/// - Student progress notes
///
/// **Migration:** Created from Note where `note.studentLesson != nil || note.studentMeeting != nil` or standalone student notes
@Model
final class StudentNote: NoteProtocol {
    // MARK: - Identity
    var id: UUID = UUID()
    
    // MARK: - Content
    var content: String = ""
    
    // MARK: - Metadata
    var createdAt: Date = Date()
    var modifiedAt: Date? = nil
    var authorID: UUID? = nil
    
    // MARK: - Category
    private var categoryRaw: String = NoteCategory.general.rawValue
    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }
    
    // MARK: - Relationship
    /// The student this note is about (REQUIRED)
    @Relationship(deleteRule: .cascade)
    var student: Student
    
    // MARK: - Optional Context Links
    /// Optional: Links to specific StudentMeeting
    var meetingID: String? = nil
    
    /// Optional: Links to specific StudentLesson
    var studentLessonID: String? = nil
    
    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        authorID: UUID? = nil,
        category: NoteCategory = .general,
        student: Student,
        meetingID: String? = nil,
        studentLessonID: String? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.authorID = authorID
        self.categoryRaw = category.rawValue
        self.student = student
        self.meetingID = meetingID
        self.studentLessonID = studentLessonID
    }
}
