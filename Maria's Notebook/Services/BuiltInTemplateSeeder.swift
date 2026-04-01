import Foundation
import CoreData
import OSLog

/// Seeds default Note and Meeting templates on first launch or after restore.
@MainActor
enum BuiltInTemplateSeeder {
    private static let logger = Logger.app(category: "TemplateSeeder")

    static func seedIfNeeded(context: NSManagedObjectContext) {
        seedNoteTemplatesIfNeeded(context: context)
        seedMeetingTemplatesIfNeeded(context: context)
    }

    // MARK: - Note Templates

    private struct NoteTemplateSeed {
        let title: String
        let body: String
        let sortOrder: Int64
    }

    private static func seedNoteTemplatesIfNeeded(context: NSManagedObjectContext) {
        let fetch = CDFetchRequest(CDNoteTemplateEntity.self)
        fetch.predicate = NSPredicate(format: "isBuiltIn == YES")
        fetch.fetchLimit = 1
        let existing = context.safeFetch(fetch)
        guard existing.isEmpty else { return }

        let templates: [NoteTemplateSeed] = [
            NoteTemplateSeed(
                title: "Observation",
                body: "What was the student doing?\nWhat materials were used?\n"
                    + "How long did they work?\nWhat did you notice?",
                sortOrder: 0
            ),
            NoteTemplateSeed(
                title: "Conference Note",
                body: "Topic discussed:\nStudent's perspective:\nAgreed next steps:\nFollow-up needed:",
                sortOrder: 1
            ),
            NoteTemplateSeed(
                title: "Incident Report",
                body: "What happened:\nWho was involved:\nHow was it resolved:\nParent communication needed:",
                sortOrder: 2
            ),
            NoteTemplateSeed(
                title: "Work Follow-Up",
                body: "Work observed:\nProgress noted:\nAreas for growth:\nSuggested next lesson:",
                sortOrder: 3
            ),
            NoteTemplateSeed(
                title: "Parent Communication",
                body: "Subject:\nKey points shared:\nParent questions/concerns:\nAction items:",
                sortOrder: 4
            )
        ]

        for t in templates {
            let template = CDNoteTemplateEntity(context: context)
            template.title = t.title
            template.body = t.body
            template.sortOrder = t.sortOrder
            template.isBuiltIn = true
        }

        logger.info("Seeded \(templates.count) built-in note templates")
    }

    // MARK: - Meeting Templates

    private static func seedMeetingTemplatesIfNeeded(context: NSManagedObjectContext) {
        let fetch = CDFetchRequest(CDMeetingTemplateEntity.self)
        fetch.predicate = NSPredicate(format: "isBuiltIn == YES")
        fetch.fetchLimit = 1
        let existing = context.safeFetch(fetch)
        guard existing.isEmpty else { return }

        let meeting = CDMeetingTemplateEntity(context: context)
        meeting.name = "Standard Student Meeting"
        meeting.reflectionPrompt = "How has your work been going? What are you most proud of recently?"
        meeting.focusPrompt = "What would you like to focus on next? Is there something new you'd like to try?"
        meeting.requestsPrompt = "Is there anything you need help with? Any materials or resources you'd like?"
        meeting.guideNotesPrompt = "Observations, follow-up items, and notes for next meeting."
        meeting.sortOrder = 0
        meeting.isActive = true
        meeting.isBuiltIn = true

        let checkIn = CDMeetingTemplateEntity(context: context)
        checkIn.name = "Quick Check-In"
        checkIn.reflectionPrompt = "How are you feeling about your work today?"
        checkIn.focusPrompt = "What's your plan for today?"
        checkIn.requestsPrompt = "Do you need anything from me?"
        checkIn.guideNotesPrompt = ""
        checkIn.sortOrder = 1
        checkIn.isActive = false
        checkIn.isBuiltIn = true

        logger.info("Seeded 2 built-in meeting templates")
    }
}
