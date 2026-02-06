import Foundation
import SwiftData

/// Note attached to Presentation (LessonAssignment) entity.
///
/// **Type Safety:** Single required relationship to Presentation
/// **Scope Support:** Can apply to all students or specific students
/// **Use Cases:**
/// - Presentation observations
/// - Lesson delivery notes
/// - Student engagement notes during presentations
///
/// **Migration:** Created from Note where `note.lessonAssignment != nil`
@Model
final class PresentationNote: NoteProtocol {
    // MARK: - Identity
    var id: UUID = UUID()
    
    // MARK: - Content
    var content: String = ""
    
    // MARK: - Metadata
    var createdAt: Date = Date()
    var modifiedAt: Date? = nil
    var authorID: UUID? = nil
    
    // MARK: - Category
    private var categoryRaw: String = NoteCategory.academic.rawValue
    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .academic }
        set { categoryRaw = newValue.rawValue }
    }
    
    // MARK: - Relationship
    /// The presentation this note is attached to (REQUIRED)
    @Relationship(deleteRule: .cascade)
    var presentation: Presentation
    
    // MARK: - Scope
    /// Scope blob for JSON encoding (stores NoteScope enum)
    @Attribute(.externalStorage) private var scopeBlob: Data?
    
    /// Note scope (all students, single student, or multiple students)
    var scope: NoteScope {
        get {
            guard let scopeBlob = scopeBlob,
                  let decoded = try? JSONDecoder().decode(NoteScope.self, from: scopeBlob) else {
                return .all
            }
            return decoded
        }
        set {
            scopeBlob = try? JSONEncoder().encode(newValue)
        }
    }
    
    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        authorID: UUID? = nil,
        category: NoteCategory = .academic,
        presentation: Presentation,
        scope: NoteScope = .all
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.authorID = authorID
        self.categoryRaw = category.rawValue
        self.presentation = presentation
        self.scope = scope
    }
}
