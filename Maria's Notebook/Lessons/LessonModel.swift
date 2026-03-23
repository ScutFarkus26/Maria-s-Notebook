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

    // MARK: - Montessori Album Fields

    /// Newline-separated list of materials needed for this lesson
    var materials: String = ""
    /// Learning objective / purpose of the lesson
    var purpose: String = ""
    /// Simple age range string (e.g., "6+", "3-6", "9-12")
    var ageRange: String = ""
    /// Teacher-specific notes separate from the presentation script (writeUp)
    var teacherNotes: String = ""

    // MARK: - Lesson Relationships

    /// Comma-separated UUIDs of lessons that are prerequisites for this lesson
    var prerequisiteLessonIDs: String = ""
    /// Comma-separated UUIDs of related/companion lessons
    var relatedLessonIDs: String = ""

    // MARK: - Cosmic Education

    /// Great Lesson connection stored as raw string (CloudKit compatible).
    /// Maps to GreatLesson enum values (e.g., "comingOfUniverse", "comingOfLife").
    var greatLessonRaw: String?

    /// Raw storage for source ("album" or "personal"). Defaults to album for backward compatibility.
    var sourceRaw: String = "album"
    /// Raw storage for optional personal kind when source is personal. Nil or empty means default .personal.
    var personalKindRaw: String?
    
    // MARK: - Story / Format

    /// Raw storage for lesson format ("standard" or "story"). Defaults to standard for backward compatibility.
    var lessonFormatRaw: String = "standard"
    /// UUID string of the parent story lesson. Nil for root stories and standard lessons.
    var parentStoryID: String?

    // MARK: - Work Configuration

    /// Raw storage for the preferred work type produced by this lesson (e.g., Practice or Follow-Up).
    var defaultWorkKindRaw: String?

    /// Store large bookmark blobs as external storage so SwiftData/CloudKit can manage them as assets.
    @Attribute(.externalStorage) var pagesFileBookmark: Data?
    /// Relative path to an imported file inside the app's managed container.
    var pagesFileRelativePath: String?
    /// Optional attachment UUID designating which attachment should act as the lesson's primary file.
    var primaryAttachmentID: String?

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

    /// Computed Great Lesson enum value (transient, not persisted)
    @Transient
    var greatLesson: GreatLesson? {
        get { greatLessonRaw.flatMap { GreatLesson(rawValue: $0) } }
        set { greatLessonRaw = newValue?.rawValue }
    }

    @Transient
    var lessonFormat: LessonFormat {
        get { LessonFormat(rawValue: lessonFormatRaw) ?? .standard }
        set { lessonFormatRaw = newValue.rawValue }
    }

    @Transient
    var parentStoryUUID: UUID? {
        get { parentStoryID.flatMap(UUID.init(uuidString:)) }
        set { parentStoryID = newValue?.uuidString }
    }

    /// Whether this lesson is a story (root or child).
    @Transient
    var isStory: Bool { lessonFormat == .story }

    /// Whether this lesson is a top-level story with no parent.
    @Transient
    var isRootStory: Bool { isStory && parentStoryID == nil }

    @Transient
    var primaryAttachmentIDUUID: UUID? {
        get { primaryAttachmentID.flatMap(UUID.init(uuidString:)) }
        set { primaryAttachmentID = newValue?.uuidString }
    }
    
    /// Helper to access suggested follow-up work as an array of individual items
    @Transient
    var suggestedFollowUpWorkItems: [String] {
        suggestedFollowUpWork
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Helper to access materials as an array of individual items
    @Transient
    var materialsItems: [String] {
        materials
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Parsed prerequisite lesson UUIDs
    @Transient
    var prerequisiteLessonUUIDs: [UUID] {
        get {
            prerequisiteLessonIDs
                .components(separatedBy: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            prerequisiteLessonIDs = newValue.map { $0.uuidString }.joined(separator: ",")
        }
    }

    /// Parsed related lesson UUIDs
    @Transient
    var relatedLessonUUIDs: [UUID] {
        get {
            relatedLessonIDs
                .components(separatedBy: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            relatedLessonIDs = newValue.map { $0.uuidString }.joined(separator: ",")
        }
    }

    /// Sample works sorted by orderIndex
    @Transient
    var sortedSampleWorks: [SampleWork] {
        (sampleWorks ?? []).sorted { $0.orderIndex < $1.orderIndex }
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

    // Relationship to SampleWork - cascade delete sample works when lesson is deleted
    @Relationship(deleteRule: .cascade, inverse: \SampleWork.lesson)
    var sampleWorks: [SampleWork]? = []

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
        primaryAttachmentID: String? = nil,
        sourceRaw: String = "album",
        personalKindRaw: String? = nil,
        defaultWorkKind: WorkKind? = nil,
        materials: String = "",
        purpose: String = "",
        ageRange: String = "",
        teacherNotes: String = "",
        prerequisiteLessonIDs: String = "",
        relatedLessonIDs: String = "",
        greatLessonRaw: String? = nil,
        lessonFormatRaw: String = "standard",
        parentStoryID: String? = nil
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
        self.primaryAttachmentID = primaryAttachmentID
        self.sourceRaw = sourceRaw
        self.personalKindRaw = personalKindRaw
        self.defaultWorkKindRaw = defaultWorkKind?.rawValue
        self.materials = materials
        self.purpose = purpose
        self.ageRange = ageRange
        self.teacherNotes = teacherNotes
        self.prerequisiteLessonIDs = prerequisiteLessonIDs
        self.relatedLessonIDs = relatedLessonIDs
        self.greatLessonRaw = greatLessonRaw
        self.lessonFormatRaw = lessonFormatRaw
        self.parentStoryID = parentStoryID
        self.notes = []
        self.lessonAssignments = []
        self.sampleWorks = []
    }
}
