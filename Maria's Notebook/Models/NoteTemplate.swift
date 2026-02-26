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

    static let builtInTemplates: [(title: String, body: String, tags: [String])] = [
        // Academic
        ("Completed independently", "Completed work independently with confidence.", [TagHelper.tagFromNoteCategory("academic")]),
        ("Showed mastery", "Demonstrated strong mastery of the material.", [TagHelper.tagFromNoteCategory("academic")]),
        ("Needs more practice", "Would benefit from additional practice with this concept.", [TagHelper.tagFromNoteCategory("academic")]),
        ("Made great progress", "Made excellent progress today.", [TagHelper.tagFromNoteCategory("academic")]),

        // Behavioral
        ("Needed redirection", "Required redirection to stay focused on task.", [TagHelper.tagFromNoteCategory("behavioral")]),
        ("Followed directions", "Followed directions well and stayed on task.", [TagHelper.tagFromNoteCategory("behavioral")]),
        ("Showed focus", "Demonstrated excellent focus and concentration.", [TagHelper.tagFromNoteCategory("behavioral")]),

        // Social
        ("Worked well with peers", "Collaborated effectively with classmates.", [TagHelper.tagFromNoteCategory("social")]),
        ("Helped others", "Showed kindness by helping a classmate.", [TagHelper.tagFromNoteCategory("social")]),
        ("Participated actively", "Actively participated in group discussion.", [TagHelper.tagFromNoteCategory("social")]),

        // Emotional
        ("Showed confidence", "Displayed confidence in their abilities.", [TagHelper.tagFromNoteCategory("emotional")]),
        ("Seemed frustrated", "Appeared frustrated; may need additional support.", [TagHelper.tagFromNoteCategory("emotional")]),
        ("Very enthusiastic", "Showed great enthusiasm for the activity.", [TagHelper.tagFromNoteCategory("emotional")]),

        // Attendance
        ("Arrived late", "Arrived late to class.", [TagHelper.tagFromNoteCategory("attendance")]),
        ("Left early", "Left class early.", [TagHelper.tagFromNoteCategory("attendance")]),

        // General
        ("Parent request", "Per parent request: ", [TagHelper.tagFromNoteCategory("general")]),
        ("Follow up needed", "Requires follow-up: ", [TagHelper.tagFromNoteCategory("general")]),
    ]

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
