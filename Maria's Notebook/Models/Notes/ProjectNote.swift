import Foundation
import SwiftData

/// Note attached to ProjectSession entity.
///
/// **Type Safety:** Single required relationship to ProjectSession
/// **Use Cases:**
/// - Project session observations
/// - Project progress notes
/// - Team collaboration notes
///
/// **Migration:** Created from Note where `note.projectSession != nil`
@Model
final class ProjectNote: NoteProtocol {
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
    /// The project session this note is attached to (REQUIRED)
    @Relationship(deleteRule: .cascade, inverse: \ProjectSession.projectNotes)
    var projectSession: ProjectSession
    
    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        authorID: UUID? = nil,
        category: NoteCategory = .general,
        projectSession: ProjectSession
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.authorID = authorID
        self.categoryRaw = category.rawValue
        self.projectSession = projectSession
    }
}

// MARK: - ProjectSession Relationship Extension
extension ProjectSession {
    /// Inverse relationship to ProjectNote
    @Relationship(deleteRule: .cascade)
    var projectNotes: [ProjectNote]? {
        get { nil } // SwiftData manages this
        set { } // SwiftData manages this
    }
}
