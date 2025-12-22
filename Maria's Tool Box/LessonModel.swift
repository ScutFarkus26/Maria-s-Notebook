import Foundation
import SwiftData

/// Core lesson model for Lessons screens persisted with SwiftData.
@Model
final class Lesson: Identifiable {
    /// Stable identifier
    var id: UUID
    /// Lesson Name
    var name: String
    /// Subject (e.g., Math, Language)
    var subject: String
    /// Group or category (e.g., Decimal System)
    var group: String
    /// Manual order within a group
    var orderInGroup: Int = 0
    /// Short subheading/strapline
    var subheading: String
    /// Markdown or rich text source for the lesson write-up
    var writeUp: String

    /// Raw storage for source ("album" or "personal"). Defaults to album for backward compatibility.
    var sourceRaw: String = "album"
    /// Raw storage for optional personal kind when source is personal. Nil or empty means default .personal.
    var personalKindRaw: String? = nil

    /// Store large bookmark blobs as external storage so SwiftData/CloudKit can manage them as assets.
    /// Note: The bookmark may contain device-specific security scope. Consider treating this as a hint only
    /// and prefer `pagesFileRelativePath` to re-resolve files within the app-managed container on each device.
    @Attribute(.externalStorage) var pagesFileBookmark: Data? = nil
    /// Relative path to an imported file inside the app's managed container (iCloud/Documents/Lesson Files or local fallback)
    var pagesFileRelativePath: String? = nil

    var source: LessonSource {
        get { LessonSource(rawValue: sourceRaw) ?? .album }
        set { sourceRaw = newValue.rawValue }
    }

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

    @Relationship var notes: [Note] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        subject: String = "",
        group: String = "",
        subheading: String = "",
        writeUp: String = "",
        pagesFileBookmark: Data? = nil,
        pagesFileRelativePath: String? = nil,
        sourceRaw: String = "album",
        personalKindRaw: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subject = subject
        self.group = group
        self.subheading = subheading
        self.writeUp = writeUp
        self.pagesFileBookmark = pagesFileBookmark
        self.pagesFileRelativePath = pagesFileRelativePath
        self.sourceRaw = sourceRaw
        self.personalKindRaw = personalKindRaw
    }
}

