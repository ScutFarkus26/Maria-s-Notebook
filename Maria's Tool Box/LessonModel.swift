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
    /// Linked Pages document bookmark
    var pagesFileBookmark: Data? = nil
    /// Relative path to an imported file inside the app's managed container (iCloud/Documents/Lesson Files or local fallback)
    var pagesFileRelativePath: String? = nil

    init(
        id: UUID = UUID(),
        name: String = "",
        subject: String = "",
        group: String = "",
        subheading: String = "",
        writeUp: String = "",
        pagesFileBookmark: Data? = nil,
        pagesFileRelativePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subject = subject
        self.group = group
        self.subheading = subheading
        self.writeUp = writeUp
        self.pagesFileBookmark = pagesFileBookmark
        self.pagesFileRelativePath = pagesFileRelativePath
    }
}

