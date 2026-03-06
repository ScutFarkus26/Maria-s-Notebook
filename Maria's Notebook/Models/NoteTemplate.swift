// NoteTemplate.swift
// Model for quick-insert note templates
//
// Templates allow teachers to quickly insert common note phrases,
// reducing repetitive typing during busy classroom moments.

import Foundation
import OSLog
import SwiftData

@Model
final class NoteTemplate: Identifiable {
    private static let logger = Logger.database

    // MARK: - Identity
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // MARK: - Content
    /// Short title displayed as a chip/button (e.g., "Completed independently")
    var title: String = ""

    /// Full template text that gets inserted (e.g., "Completed work independently with confidence.")
    var body: String = ""

    /// Legacy category field — kept for migration; new code uses `tags`
    private var categoryRaw: String = NoteCategory.general.rawValue

    /// Legacy computed property — reads from categoryRaw for migration; prefer `tags`
    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

    /// The legacy categoryRaw value (read-only, for migration)
    var legacyCategoryRaw: String { categoryRaw }

    /// Tags in "Name|Color" format to auto-apply when this template is used
    var tags: [String] = []

    // MARK: - Organization
    /// Display order in the template list (lower = first)
    var sortOrder: Int = 0

    /// Whether this is a built-in template (not editable/deletable by user)
    var isBuiltIn: Bool = false

    // MARK: - Initializers

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        body: String,
        tags: [String] = [],
        sortOrder: Int = 0,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.tags = tags
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }

    // MARK: - Built-in Templates

    struct BuiltInTemplate {
        let title: String
        let body: String
        let tags: [String]
    }

    // swiftlint:disable line_length
    static let builtInTemplates: [BuiltInTemplate] = [
        // Academic
        .init(title: "Completed independently", body: "Completed work independently with confidence.", tags: [TagHelper.tagFromNoteCategory("academic")]),
        .init(title: "Showed mastery", body: "Demonstrated strong mastery of the material.", tags: [TagHelper.tagFromNoteCategory("academic")]),
        .init(title: "Needs more practice", body: "Would benefit from additional practice with this concept.", tags: [TagHelper.tagFromNoteCategory("academic")]),
        .init(title: "Made great progress", body: "Made excellent progress today.", tags: [TagHelper.tagFromNoteCategory("academic")]),

        // Behavioral
        .init(title: "Needed redirection", body: "Required redirection to stay focused on task.", tags: [TagHelper.tagFromNoteCategory("behavioral")]),
        .init(title: "Followed directions", body: "Followed directions well and stayed on task.", tags: [TagHelper.tagFromNoteCategory("behavioral")]),
        .init(title: "Showed focus", body: "Demonstrated excellent focus and concentration.", tags: [TagHelper.tagFromNoteCategory("behavioral")]),

        // Social
        .init(title: "Worked well with peers", body: "Collaborated effectively with classmates.", tags: [TagHelper.tagFromNoteCategory("social")]),
        .init(title: "Helped others", body: "Showed kindness by helping a classmate.", tags: [TagHelper.tagFromNoteCategory("social")]),
        .init(title: "Participated actively", body: "Actively participated in group discussion.", tags: [TagHelper.tagFromNoteCategory("social")]),

        // Emotional
        .init(title: "Showed confidence", body: "Displayed confidence in their abilities.", tags: [TagHelper.tagFromNoteCategory("emotional")]),
        .init(title: "Seemed frustrated", body: "Appeared frustrated; may need additional support.", tags: [TagHelper.tagFromNoteCategory("emotional")]),
        .init(title: "Very enthusiastic", body: "Showed great enthusiasm for the activity.", tags: [TagHelper.tagFromNoteCategory("emotional")]),

        // Attendance
        .init(title: "Arrived late", body: "Arrived late to class.", tags: [TagHelper.tagFromNoteCategory("attendance")]),
        .init(title: "Left early", body: "Left class early.", tags: [TagHelper.tagFromNoteCategory("attendance")]),

        // General
        .init(title: "Parent request", body: "Per parent request: ", tags: [TagHelper.tagFromNoteCategory("general")]),
        .init(title: "Follow up needed", body: "Requires follow-up: ", tags: [TagHelper.tagFromNoteCategory("general")])
    ]
    // swiftlint:enable line_length

    /// Seeds the built-in templates into the database if they don't exist.
    static func seedBuiltInTemplates(in context: ModelContext) {
        // Check if any built-in templates exist
        let fetch = FetchDescriptor<NoteTemplate>(
            predicate: #Predicate<NoteTemplate> { template in
                template.isBuiltIn == true
            }
        )
        let existing: [NoteTemplate]
        do {
            existing = try context.fetch(fetch)
        } catch {
            logger.warning("Failed to fetch existing note templates: \(error.localizedDescription)")
            return
        }

        guard existing.isEmpty else { return }

        // Create built-in templates
        for (index, templateData) in builtInTemplates.enumerated() {
            let template = NoteTemplate(
                title: templateData.title,
                body: templateData.body,
                tags: templateData.tags,
                sortOrder: index,
                isBuiltIn: true
            )
            context.insert(template)
        }

        do {
            try context.save()
        } catch {
            logger.warning("Failed to save built-in note templates: \(error.localizedDescription)")
        }
    }
}
