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

    /// The category to auto-select when this template is used
    private var categoryRaw: String = NoteCategory.general.rawValue

    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

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
        category: NoteCategory = .general,
        sortOrder: Int = 0,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.categoryRaw = category.rawValue
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }

    // MARK: - Built-in Templates

    nonisolated(unsafe) static let builtInTemplates: [(title: String, body: String, category: NoteCategory)] = [
        // Academic
        ("Completed independently", "Completed work independently with confidence.", .academic),
        ("Showed mastery", "Demonstrated strong mastery of the material.", .academic),
        ("Needs more practice", "Would benefit from additional practice with this concept.", .academic),
        ("Made great progress", "Made excellent progress today.", .academic),

        // Behavioral
        ("Needed redirection", "Required redirection to stay focused on task.", .behavioral),
        ("Followed directions", "Followed directions well and stayed on task.", .behavioral),
        ("Showed focus", "Demonstrated excellent focus and concentration.", .behavioral),

        // Social
        ("Worked well with peers", "Collaborated effectively with classmates.", .social),
        ("Helped others", "Showed kindness by helping a classmate.", .social),
        ("Participated actively", "Actively participated in group discussion.", .social),

        // Emotional
        ("Showed confidence", "Displayed confidence in their abilities.", .emotional),
        ("Seemed frustrated", "Appeared frustrated; may need additional support.", .emotional),
        ("Very enthusiastic", "Showed great enthusiasm for the activity.", .emotional),

        // Attendance
        ("Arrived late", "Arrived late to class.", .attendance),
        ("Left early", "Left class early.", .attendance),

        // General
        ("Parent request", "Per parent request: ", .general),
        ("Follow up needed", "Requires follow-up: ", .general),
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
                category: templateData.category,
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
