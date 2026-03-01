import Foundation
import SwiftData

/// Core lesson model for Lessons screens persisted with SwiftData.
@Model
final class Lesson: Identifiable {
    #Index<Lesson>([\.subject, \.sortIndex], [\.name])

    /// Stable identifier
    var id: UUID = UUID()
    /// Lesson Name
    var name: String = ""
    /// Subject (e.g., Math, Language)
    var subject: String = ""
    /// Group or category (e.g., Decimal System)
    var group: String = ""
    /// Manual order within a group
    var orderInGroup: Int = 0
    /// Ordering index for lessons within a subject (across all groups)
    var sortIndex: Int = 0
    /// Short subheading/strapline
    var subheading: String = ""
    /// Markdown or rich text source for the lesson write-up
    var writeUp: String = ""
    /// Suggested follow-up work items (newline-separated list)
    var suggestedFollowUpWork: String = ""

    /// Raw storage for source ("album" or "personal"). Defaults to album for backward compatibility.
    var sourceRaw: String = "album"
    /// Raw storage for optional personal kind when source is personal. Nil or empty means default .personal.
    var personalKindRaw: String? = nil
    
    // MARK: - Work Configuration
    
    /// Raw storage for the preferred work type produced by this lesson (e.g., Practice or Follow-Up).
    var defaultWorkKindRaw: String? = nil

    /// Store large bookmark blobs as external storage so SwiftData/CloudKit can manage them as assets.
    @Attribute(.externalStorage) var pagesFileBookmark: Data? = nil
    /// Relative path to an imported file inside the app's managed container.
    var pagesFileRelativePath: String? = nil

    // MARK: - Computed Properties

    @Transient
    var source: LessonSource {
        get { LessonSource(rawValue: sourceRaw) ?? .album }
        set { sourceRaw = newValue.rawValue }
    }

    @Transient
    var personalKind: PersonalLessonKind? {
        get {
            guard source == .personal else { return nil }
            guard let raw = personalKindRaw else { return .personal }
            return PersonalLessonKind(rawValue: raw) ?? .personal
        }
        set {
            if source != .personal { personalKindRaw = nil; return }
            personalKindRaw = (newValue ?? .personal).rawValue
        }
    }
    
    /// The preferred work kind for this lesson. Used to automatically categorize work spawned from presentations.
    @Transient
    var defaultWorkKind: WorkKind? {
        get { defaultWorkKindRaw.flatMap { WorkKind(rawValue: $0) } }
        set { defaultWorkKindRaw = newValue?.rawValue }
    }
    
    /// Helper to access suggested follow-up work as an array of individual items
    @Transient
    var suggestedFollowUpWorkItems: [String] {
        suggestedFollowUpWork
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // FIX: Made optional for CloudKit
    // Relationship with explicit inverse and cascade delete rule
    @Relationship(deleteRule: .cascade, inverse: \Note.lesson) var notes: [Note]? = []
    
    // Relationship to LessonAssignment - cascade deletes assignments when lesson is deleted
    @Relationship(deleteRule: .cascade, inverse: \LessonAssignment.lesson)
    var lessonAssignments: [LessonAssignment]? = []
    
    // Relationship to LessonAttachment - cascade delete attachments when lesson is deleted
    @Relationship(deleteRule: .cascade, inverse: \LessonAttachment.lesson)
    var attachments: [LessonAttachment]? = []

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String = "",
        subject: String = "",
        group: String = "",
        orderInGroup: Int = 0,
        sortIndex: Int = 0,
        subheading: String = "",
        writeUp: String = "",
        suggestedFollowUpWork: String = "",
        pagesFileBookmark: Data? = nil,
        pagesFileRelativePath: String? = nil,
        sourceRaw: String = "album",
        personalKindRaw: String? = nil,
        defaultWorkKind: WorkKind? = nil
    ) {
        self.id = id
        self.name = name
        self.subject = subject
        self.group = group
        self.orderInGroup = orderInGroup
        self.sortIndex = sortIndex
        self.subheading = subheading
        self.writeUp = writeUp
        self.suggestedFollowUpWork = suggestedFollowUpWork
        self.pagesFileBookmark = pagesFileBookmark
        self.pagesFileRelativePath = pagesFileRelativePath
        self.sourceRaw = sourceRaw
        self.personalKindRaw = personalKindRaw
        self.defaultWorkKindRaw = defaultWorkKind?.rawValue
        self.notes = []
        self.lessonAssignments = []
    }
}
