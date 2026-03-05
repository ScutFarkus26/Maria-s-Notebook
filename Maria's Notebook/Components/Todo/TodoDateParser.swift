import Foundation

/// Lightweight, synchronous natural language date parser for todo quick-add.
/// No AI dependency — uses regex patterns for common date phrases.
struct TodoDateParser {
    struct ParseResult {
        /// Title with matched date text removed
        var cleanTitle: String
        /// The date that was parsed, if any
        var suggestedDate: Date?
        /// The original text that matched (e.g., "tomorrow")
        var matchedText: String?
    }

    private static let calendar = Calendar.current

    /// Parse a todo title for date phrases and return a clean title + suggested date.
    static func parse(_ input: String) -> ParseResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParseResult(cleanTitle: trimmed, suggestedDate: nil, matchedText: nil)
        }

        let today = AppCalendar.startOfDay(Date())

        // Try each pattern in priority order
        for pattern in patterns {
            if let match = pattern.regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range, in: trimmed) {
                let matchedText = String(trimmed[range])
                if let date = pattern.resolve(match, trimmed, today) {
                    let cleaned = trimmed.replacingCharacters(in: range, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "  ", with: " ")
                    return ParseResult(
                        cleanTitle: cleaned.isEmpty ? trimmed : cleaned,
                        suggestedDate: date,
                        matchedText: matchedText
                    )
                }
            }
        }

        return ParseResult(cleanTitle: trimmed, suggestedDate: nil, matchedText: nil)
    }

    // MARK: - Pattern Definitions

    private struct DatePattern {
        let regex: NSRegularExpression
        let resolve: (NSTextCheckingResult, String, Date) -> Date?
    }

    // swiftlint:disable force_try
    private nonisolated(unsafe) static let patterns: [DatePattern] = [
        // "today" / "tonight"
        DatePattern(
            regex: try! NSRegularExpression(pattern: "\\b(today|tonight)\\b", options: .caseInsensitive),
            resolve: { _, _, today in today }
        ),

        // "tomorrow" / "tmr" / "tmrw"
        DatePattern(
            regex: try! NSRegularExpression(pattern: "\\b(tomorrow|tmr|tmrw)\\b", options: .caseInsensitive),
            resolve: { _, _, today in calendar.date(byAdding: .day, value: 1, to: today) }
        ),

        // "next week"
        DatePattern(
            regex: try! NSRegularExpression(pattern: "\\bnext\\s+week\\b", options: .caseInsensitive),
            resolve: { _, _, today in nextWeekday(2, after: today) } // Monday
        ),

        // "next monday" ... "next sunday"
        DatePattern(
            // swiftlint:disable:next line_length
            regex: try! NSRegularExpression(pattern: "\\bnext\\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\\b", options: .caseInsensitive),
            resolve: { match, input, today in
                guard let dayRange = Range(match.range(at: 1), in: input) else { return nil }
                let dayStr = String(input[dayRange]).lowercased()
                guard let weekday = weekdayNumber(dayStr) else { return nil }
                // "next X" always means the X in the following week
                return nextWeekday(weekday, after: today, skipThisWeek: true)
            }
        ),

        // Bare weekday: "monday" ... "sunday" (coming occurrence)
        DatePattern(
            // swiftlint:disable:next line_length
            regex: try! NSRegularExpression(pattern: "\\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\\b", options: .caseInsensitive),
            resolve: { match, input, today in
                guard let dayRange = Range(match.range(at: 1), in: input) else { return nil }
                let dayStr = String(input[dayRange]).lowercased()
                guard let weekday = weekdayNumber(dayStr) else { return nil }
                return nextWeekday(weekday, after: today)
            }
        ),

        // "in N days"
        DatePattern(
            regex: try! NSRegularExpression(pattern: "\\bin\\s+(\\d+)\\s+days?\\b", options: .caseInsensitive),
            resolve: { match, input, today in
                guard let numRange = Range(match.range(at: 1), in: input),
                      let days = Int(input[numRange]) else { return nil }
                return calendar.date(byAdding: .day, value: days, to: today)
            }
        ),

        // "in N weeks"
        DatePattern(
            regex: try! NSRegularExpression(pattern: "\\bin\\s+(\\d+)\\s+weeks?\\b", options: .caseInsensitive),
            resolve: { match, input, today in
                guard let numRange = Range(match.range(at: 1), in: input),
                      let weeks = Int(input[numRange]) else { return nil }
                return calendar.date(byAdding: .weekOfYear, value: weeks, to: today)
            }
        ),

        // "jan 15", "january 15", "feb 3", etc.
        DatePattern(
            // swiftlint:disable:next line_length
            regex: try! NSRegularExpression(pattern: "\\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\\s+(\\d{1,2})\\b", options: .caseInsensitive),
            resolve: { match, input, today in
                guard let monthRange = Range(match.range(at: 1), in: input),
                      let dayRange = Range(match.range(at: 2), in: input),
                      let day = Int(input[dayRange]) else { return nil }
                let monthStr = String(input[monthRange]).lowercased()
                guard let month = monthNumber(monthStr) else { return nil }
                return resolveMonthDay(month: month, day: day, after: today)
            }
        ),

        // "1/15", "01/15" (M/D format)
        DatePattern(
            regex: try! NSRegularExpression(pattern: "\\b(\\d{1,2})/(\\d{1,2})\\b", options: []),
            resolve: { match, input, today in
                guard let mRange = Range(match.range(at: 1), in: input),
                      let dRange = Range(match.range(at: 2), in: input),
                      let month = Int(input[mRange]),
                      let day = Int(input[dRange]),
                      month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
                return resolveMonthDay(month: month, day: day, after: today)
            }
        )
    ]
    // swiftlint:enable force_try

    // MARK: - Helpers

    private static func weekdayNumber(_ str: String) -> Int? {
        switch str {
        case "sunday", "sun": return 1
        case "monday", "mon": return 2
        case "tuesday", "tue": return 3
        case "wednesday", "wed": return 4
        case "thursday", "thu": return 5
        case "friday", "fri": return 6
        case "saturday", "sat": return 7
        default: return nil
        }
    }

    private static func monthNumber(_ str: String) -> Int? {
        let months = [
            "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
            "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6,
            "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "september": 9,
            "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12
        ]
        return months[str]
    }

    /// Find the next occurrence of a given weekday (1=Sun ... 7=Sat).
    private static func nextWeekday(_ weekday: Int, after date: Date, skipThisWeek: Bool = false) -> Date? {
        var current = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        if skipThisWeek {
            // Jump to next week first
            current = calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
            // Then find the target weekday in that week
            let currentWeekday = calendar.component(.weekday, from: current)
            let diff = (weekday - currentWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: diff, to: current)
        }
        // Find the nearest upcoming occurrence
        for _ in 0..<7 {
            if calendar.component(.weekday, from: current) == weekday {
                return current
            }
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return current
    }

    /// Resolve a month/day to the next occurrence (this year or next).
    private static func resolveMonthDay(month: Int, day: Int, after today: Date) -> Date? {
        let year = calendar.component(.year, from: today)
        var comps = DateComponents(year: year, month: month, day: day)
        if let date = calendar.date(from: comps), date >= today {
            return date
        }
        // Try next year
        comps.year = year + 1
        return calendar.date(from: comps)
    }
}
