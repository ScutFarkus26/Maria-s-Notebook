import Foundation
import FoundationModels

/// Service for parsing natural language todo input using Apple Intelligence
struct TodoSmartParserService {
    @Generable(description: "Parsed todo information from natural language input")
    struct ParsedTodo {
        @Guide(description: "The clean task title without date/priority markers")
        var title: String
        
        @Guide(description: "Priority level: none, low, medium, or high")
        var priority: String
        
        @Guide(description: "Due date in ISO 8601 format if mentioned (e.g., '2026-02-15'), otherwise empty string")
        var dueDate: String
        
        @Guide(description: "Recurrence pattern: none, daily, weekdays, weekly, biweekly, monthly, or yearly")
        var recurrence: String
    }
    
    static func parseTodo(from text: String) async throws -> ParsedTodo {
        let prompt = """
        Parse this todo item and extract structured information:
        
        "\(text)"
        
        Extract:
        1. Clean title (remove markers like "tomorrow", "urgent", etc.)
        2. Priority level based on words like urgent, important, ASAP (high), or normal/regular (medium), or later/someday (low)
        3. Due date if mentioned (today, tomorrow, next week, specific dates, etc.) - use ISO 8601 format
        4. Recurrence if mentioned (daily, every day, weekdays, weekly, every week, monthly, yearly)
        
        Default to "none" priority, empty dueDate, and "none" recurrence if not clearly specified.
        """
        
        let session = LanguageModelSession(model: .default)
        let response = try await session.respond(
            to: prompt,
            generating: ParsedTodo.self
        )
        
        return response.content
    }
}
