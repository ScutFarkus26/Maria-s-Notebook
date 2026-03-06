import Foundation
import SwiftData

/// A classroom resource document (PDF) stored in the Resource Library.
/// Unlike `Document` (which is student-specific), resources are standalone items
/// organized by category and tags for quick classroom reference.
@Model
final class Resource: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var descriptionText: String = ""
    var categoryRaw: String = ResourceCategory.other.rawValue

    // File storage (follows LessonAttachment pattern)
    @Attribute(.externalStorage) var fileBookmark: Data?
    var fileRelativePath: String = ""
    var fileSizeBytes: Int64 = 0
    @Attribute(.externalStorage) var thumbnailData: Data?

    // Organization
    var tags: [String] = []
    var isFavorite: Bool = false
    var lastViewedAt: Date?

    // Linked entity IDs (comma-separated strings for CloudKit compatibility)
    var linkedLessonIDs: String = ""
    var linkedSubjects: String = ""

    // Timestamps
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    // MARK: - Computed Properties

    @Transient
    var category: ResourceCategory {
        get { ResourceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    @Transient
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        title: String = "",
        descriptionText: String = "",
        category: ResourceCategory = .other,
        fileBookmark: Data? = nil,
        fileRelativePath: String = "",
        fileSizeBytes: Int64 = 0,
        thumbnailData: Data? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        linkedLessonIDs: String = "",
        linkedSubjects: String = ""
    ) {
        self.id = id
        self.title = title
        self.descriptionText = descriptionText
        self.categoryRaw = category.rawValue
        self.fileBookmark = fileBookmark
        self.fileRelativePath = fileRelativePath
        self.fileSizeBytes = fileSizeBytes
        self.thumbnailData = thumbnailData
        self.tags = tags
        self.isFavorite = isFavorite
        self.linkedLessonIDs = linkedLessonIDs
        self.linkedSubjects = linkedSubjects
    }
}

// MARK: - ResourceCategory

enum ResourceCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case writingPapers = "Writing Papers"
    case printableMaterials = "Printable Materials"
    case curriculumGuides = "Curriculum Guides"
    case referenceCharts = "Reference Charts"
    case formsTemplates = "Forms & Templates"
    case assessmentTools = "Assessment Tools"
    case parentCommunication = "Parent Communication"
    case practicalLife = "Practical Life"
    case sensorial = "Sensorial"
    case math = "Math"
    case language = "Language"
    case science = "Science"
    case geography = "Geography"
    case art = "Art"
    case music = "Music"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .writingPapers: return "doc.richtext"
        case .printableMaterials: return "printer"
        case .curriculumGuides: return "book"
        case .referenceCharts: return "chart.bar.doc.horizontal"
        case .formsTemplates: return "doc.on.clipboard"
        case .assessmentTools: return "checkmark.seal"
        case .parentCommunication: return "envelope"
        case .practicalLife: return "hands.sparkles"
        case .sensorial: return "hand.point.up.braille"
        case .math: return "number"
        case .language: return "textformat.abc"
        case .science: return "leaf"
        case .geography: return "globe.americas"
        case .art: return "paintpalette"
        case .music: return "music.note"
        case .other: return "doc"
        }
    }
}
