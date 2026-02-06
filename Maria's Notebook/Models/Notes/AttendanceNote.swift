import Foundation
import SwiftData

/// Note attached to AttendanceRecord entity.
///
/// **Type Safety:** Single required relationship to AttendanceRecord
/// **Use Cases:**
/// - Attendance-related observations
/// - Absence reasons and explanations
/// - Attendance pattern notes
///
/// **Migration:** Created from Note where `note.attendanceRecord != nil`
@Model
final class AttendanceNote: NoteProtocol {
    // MARK: - Identity
    var id: UUID = UUID()
    
    // MARK: - Content
    var content: String = ""
    
    // MARK: - Metadata
    var createdAt: Date = Date()
    var modifiedAt: Date? = nil
    var authorID: UUID? = nil
    
    // MARK: - Category
    private var categoryRaw: String = NoteCategory.attendance.rawValue
    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .attendance }
        set { categoryRaw = newValue.rawValue }
    }
    
    // MARK: - Relationship
    /// The attendance record this note is attached to (REQUIRED)
    @Relationship(deleteRule: .cascade)
    var attendance: AttendanceRecord
    
    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        authorID: UUID? = nil,
        category: NoteCategory = .attendance,
        attendance: AttendanceRecord
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.authorID = authorID
        self.categoryRaw = category.rawValue
        self.attendance = attendance
    }
}
