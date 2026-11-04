import Foundation
import CoreData
import OSLog

/// Seeds the built-in meeting templates on first launch or after restore.
///
/// Waits while the store is still receiving its first download from iCloud:
/// the notebook's own built-ins are on their way down, and seeding the empty
/// store beside them is what left a second set after every reset. The seed
/// runs once the download finishes (`FirstDownloadGate`), and only if none
/// arrived.
enum BuiltInTemplateSeeder {
    private static let logger = Logger.templateSeeder

    static func seedIfNeeded(context: NSManagedObjectContext, defaults: UserDefaults = .standard) {
        guard !FirstDownloadGate.isPending(defaults: defaults) else {
            logger.info("Built-in templates wait for the first download from iCloud")
            return
        }
        seedMeetingTemplatesIfNeeded(context: context)
    }

    // MARK: - Meeting Templates

    private static func seedMeetingTemplatesIfNeeded(context: NSManagedObjectContext) {
        let fetch = CDFetchRequest(CDMeetingTemplate.self)
        fetch.predicate = NSPredicate(format: "isBuiltIn == YES")
        fetch.fetchLimit = 1
        let existing = context.safeFetch(fetch)
        guard existing.isEmpty else { return }

        let meeting = CDMeetingTemplate(context: context)
        meeting.name = "Standard Student Meeting"
        meeting.reflectionPrompt = "How has your work been going? What are you most proud of recently?"
        meeting.focusPrompt = "What would you like to focus on next? Is there something new you'd like to try?"
        meeting.requestsPrompt = "Is there anything you need help with? Any materials or resources you'd like?"
        meeting.guideNotesPrompt = "Observations, follow-up items, and notes for next meeting."
        meeting.sortOrder = 0
        meeting.isActive = true
        meeting.isBuiltIn = true

        let checkIn = CDMeetingTemplate(context: context)
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
