import Foundation
import SwiftData

/// Note attached to Work-related entities (WorkModel, WorkCheckIn, WorkCompletionRecord, WorkPlanItem).
///
/// **Type Safety:** Single required relationship to WorkModel
/// **Optional Links:** Can link to WorkCheckIn, WorkCompletionRecord, or WorkPlanItem
/// **Use Cases:**
/// - Work progress observations
/// - Work check-in notes
/// - Work completion notes
/// - Work plan item notes
///
/// **Migration:** Created from Note where `note.work != nil || note.workCheckIn != nil || note.workCompletionRecord != nil || note.workPlanItem != nil`
@Model
final class WorkNote: NoteProtocol {
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
    /// The work item this note is attached to (REQUIRED)
    @Relationship(deleteRule: .cascade)
    var work: WorkModel
    
    // MARK: - Optional Context Links
    /// Optional: Links to specific WorkCheckIn
    var checkInID: String? = nil
    
    /// Optional: Links to specific WorkCompletionRecord
    var completionRecordID: String? = nil
    
    /// Optional: Links to specific WorkPlanItem
    var workPlanItemID: String? = nil
    
    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        authorID: UUID? = nil,
        category: NoteCategory = .general,
        work: WorkModel,
        checkInID: String? = nil,
        completionRecordID: String? = nil,
        workPlanItemID: String? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.authorID = authorID
        self.categoryRaw = category.rawValue
        self.work = work
        self.checkInID = checkInID
        self.completionRecordID = completionRecordID
        self.workPlanItemID = workPlanItemID
    }
}
