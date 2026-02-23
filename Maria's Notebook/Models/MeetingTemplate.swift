// MeetingTemplate.swift
// Model for weekly meeting templates
//
// Templates define the placeholder prompts shown in the weekly meeting form,
// allowing teachers to customize the questions for reflection, focus, requests, and notes.

import Foundation
import SwiftData

@Model
final class MeetingTemplate: Identifiable {
    // MARK: - Identity
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // MARK: - Content
    /// Name of this template (e.g., "Default", "End of Year", "Goal Setting")
    var name: String = ""

    /// Placeholder prompt for student reflection field
    var reflectionPrompt: String = ""

    /// Placeholder prompt for focus/goals field
    var focusPrompt: String = ""

    /// Placeholder prompt for lesson requests field
    var requestsPrompt: String = ""

    /// Placeholder prompt for guide notes field
    var guideNotesPrompt: String = ""

    // MARK: - Organization
    /// Display order in the template list (lower = first)
    var sortOrder: Int = 0

    /// Whether this is the currently active template
    var isActive: Bool = false

    /// Whether this is a built-in template (not deletable by user)
    var isBuiltIn: Bool = false

    // MARK: - Initializers

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String,
        reflectionPrompt: String,
        focusPrompt: String,
        requestsPrompt: String,
        guideNotesPrompt: String,
        sortOrder: Int = 0,
        isActive: Bool = false,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.reflectionPrompt = reflectionPrompt
        self.focusPrompt = focusPrompt
        self.requestsPrompt = requestsPrompt
        self.guideNotesPrompt = guideNotesPrompt
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.isBuiltIn = isBuiltIn
    }

    // MARK: - Built-in Templates

    static let defaultTemplate = (
        name: "Default",
        reflectionPrompt: "What went well? What was hard?",
        focusPrompt: "1–3 priorities for this week…",
        requestsPrompt: "Lessons the student wants…",
        guideNotesPrompt: "Observations only…"
    )

    static let goalSettingTemplate = (
        name: "Goal Setting",
        reflectionPrompt: "What goals did you work on? How did it go?",
        focusPrompt: "What new goals would you like to set?",
        requestsPrompt: "What lessons would help you reach your goals?",
        guideNotesPrompt: "Notes on student's goal progress…"
    )

    static let endOfWeekTemplate = (
        name: "End of Week",
        reflectionPrompt: "What was your biggest accomplishment this week?",
        focusPrompt: "What do you want to carry into next week?",
        requestsPrompt: "Any lessons you'd like to revisit or try?",
        guideNotesPrompt: "Weekly summary notes…"
    )

    static let builtInTemplates: [(name: String, reflectionPrompt: String, focusPrompt: String, requestsPrompt: String, guideNotesPrompt: String)] = [
        defaultTemplate,
        goalSettingTemplate,
        endOfWeekTemplate
    ]

    /// Seeds the built-in templates into the database if they don't exist.
    @MainActor
    static func seedBuiltInTemplates(in context: ModelContext) {
        // Check if any built-in templates exist
        let fetch = FetchDescriptor<MeetingTemplate>(
            predicate: #Predicate<MeetingTemplate> { template in
                template.isBuiltIn == true
            }
        )
        let existing: [MeetingTemplate]
        do {
            existing = try context.fetch(fetch)
        } catch {
            print("⚠️ [\(#function)] Failed to fetch existing templates: \(error)")
            return
        }

        guard existing.isEmpty else { return }

        // Create built-in templates
        for (index, templateData) in builtInTemplates.enumerated() {
            let template = MeetingTemplate(
                name: templateData.name,
                reflectionPrompt: templateData.reflectionPrompt,
                focusPrompt: templateData.focusPrompt,
                requestsPrompt: templateData.requestsPrompt,
                guideNotesPrompt: templateData.guideNotesPrompt,
                sortOrder: index,
                isActive: index == 0, // First template is active by default
                isBuiltIn: true
            )
            context.insert(template)
        }

        do {
            try context.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save built-in templates: \(error)")
        }
    }
}
