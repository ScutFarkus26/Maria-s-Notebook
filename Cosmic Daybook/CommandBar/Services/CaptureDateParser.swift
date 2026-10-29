// CaptureDateParser.swift
// The day a captured presentation was given, read from the guide's words.

import Foundation

/// Reads the day out of a capture like "Yesterday I gave Maya the binomial
/// cube" or "On Tuesday I showed Leah the map". Only days in the last school
/// week count (today and the seven days before it), never a day still to come
/// ("next Tuesday" is passed over: the day is when the lesson was given);
/// anything else, or no day at all, means today. The review screen shows the
/// day so she can change it.
nonisolated enum CaptureDateParser {
    /// How far back a named day can reach: the last school week.
    static let lookBackDays = 7

    /// The start of the day the words name, or the start of `today`.
    static func day(in text: String, today: Date, calendar: Calendar = AppCalendar.shared) -> Date {
        let todayStart = calendar.startOfDay(for: today)
        let earliest = calendar.date(byAdding: .day, value: -lookBackDays, to: todayStart) ?? todayStart
        let lower = text.lowercased()

        // Every mention, in the order she said them; the first one that names
        // a day in range wins.
        let mentions = (relativeMentions(in: lower, todayStart: todayStart, calendar: calendar)
            + weekdayMentions(in: lower, todayStart: todayStart, calendar: calendar)
            + monthDayMentions(in: lower, todayStart: todayStart, calendar: calendar)
            + numericMentions(in: lower, todayStart: todayStart, calendar: calendar))
            .sorted { $0.position < $1.position }

        for mention in mentions {
            guard let day = mention.day else { continue }
            let start = calendar.startOfDay(for: day)
            if start >= earliest && start <= todayStart {
                return start
            }
        }
        return todayStart
    }

    /// When to stamp what's saved for `day`: now if it's today, so today's
    /// captures keep their order among the day's other records, and the start
    /// of the day for an earlier day.
    static func moment(on day: Date, now: Date, calendar: Calendar = AppCalendar.shared) -> Date {
        calendar.isDate(day, inSameDayAs: now) ? now : calendar.startOfDay(for: day)
    }

    private struct Mention {
        let position: String.Index
        let day: Date?
    }

    // MARK: - Kinds of mention

    private static func relativeMentions(in text: String, todayStart: Date, calendar: Calendar) -> [Mention] {
        let today = text.matches(of: /\b(today|this morning|this afternoon)\b/).map {
            Mention(position: $0.range.lowerBound, day: todayStart)
        }
        let yesterday = text.matches(of: /\byesterday\b/).map {
            Mention(position: $0.range.lowerBound, day: calendar.date(byAdding: .day, value: -1, to: todayStart))
        }
        return today + yesterday
    }

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// A weekday counts only where it reads as the day something happened
    /// (bug hunt 2026-10-29, #19: any weekday anywhere used to): "on
    /// Tuesday", "last Tuesday", "this past Tuesday", "this Tuesday", or
    /// "Tuesday" standing alone as the date, opening a sentence or closing
    /// one ("I gave her the cube Tuesday."), "Tuesday morning" too. One that
    /// describes something else names no day: "her Tuesday work plan",
    /// "Monday's spelling", "by Friday", "every Monday".
    ///
    /// "Tuesday" is the latest Tuesday up to today; "last Tuesday" said on a
    /// Tuesday is the week before; "this Tuesday" is this week's. "Next
    /// Tuesday" (and "this Tuesday" when it hasn't come yet) is still to come:
    /// a lesson can't have been given then, so it is passed over, and the day
    /// comes from her other words or is today.
    private static func weekdayMentions(in text: String, todayStart: Date, calendar: Calendar) -> [Mention] {
        let todayWeekday = calendar.component(.weekday, from: todayStart)
        let pattern = #/
            \b (?: (on|last|this\ past|past|this\ coming|coming|next|this) \  )?
            (sunday|monday|tuesday|wednesday|thursday|friday|saturday) \b
            /#
        return text.matches(of: pattern).compactMap { match in
            guard let index = weekdays.firstIndex(of: String(match.output.2)) else { return nil }
            let weekday = index + 1
            let daysBack = (todayWeekday - weekday + 7) % 7
            let offset: Int
            switch match.output.1.map(String.init) {
            case "on"?, "past"?, "this past"?:
                offset = -daysBack
            case "last"?:
                offset = daysBack == 0 ? -7 : -daysBack
            case "this"?:
                // This week's, which may be still to come.
                offset = weekday - todayWeekday
            case "next"?, "coming"?, "this coming"?:
                offset = daysBack == 0 ? 7 : 7 - daysBack
            default:
                guard weekdayStandsAlone(match.range, in: text) else { return nil }
                offset = -daysBack
            }
            return Mention(
                position: match.range.lowerBound,
                day: calendar.date(byAdding: .day, value: offset, to: todayStart)
            )
        }
    }

    /// Whether a weekday with nothing before it is said as the date: it opens
    /// a sentence ("Tuesday I showed Leah the map"), not as a possessive, or
    /// it closes a clause ("…the map Tuesday.", "…Tuesday morning, and"),
    /// and isn't a deadline or a habit ("by Friday", "every Monday").
    private static func weekdayStandsAlone(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let after = text[range.upperBound...]
        if before.isEmpty || ".!?;:\n".contains(before.last ?? " ") {
            return after.prefixMatch(of: /['’]s\b/) == nil
        }
        let previousWord = before.split(whereSeparator: { !$0.isLetter }).last.map(String.init) ?? ""
        guard !["by", "until", "till", "every", "each", "for", "before"].contains(previousWord) else { return false }
        return after.prefixMatch(of: /(?: (?:morning|afternoon|evening))?\s*(?:$|[,.;:!?—])/) != nil
    }

    private static let months = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
    ]

    /// "October 8", "Oct 8th", "Sept. 30". Only month names and their usual
    /// short forms count, so "Maya 2" isn't May 2.
    private static func monthDayMentions(in text: String, todayStart: Date, calendar: Calendar) -> [Mention] {
        let pattern = #/
            \b (january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug
                |september|sept|sep|october|oct|november|nov|december|dec) \b \.? \s (\d{1,2}) (?:st|nd|rd|th)? \b
            /#
        return text.matches(of: pattern).compactMap { match in
            guard let month = months.firstIndex(of: String(match.output.1.prefix(3))),
                  let day = Int(match.output.2) else { return nil }
            return Mention(
                position: match.range.lowerBound,
                day: latestDate(month: month + 1, day: day, todayStart: todayStart, calendar: calendar)
            )
        }
    }

    /// "on 10/8" (month first). The "on" keeps fractions like "3/4" out.
    private static func numericMentions(in text: String, todayStart: Date, calendar: Calendar) -> [Mention] {
        text.matches(of: /\bon (\d{1,2})\/(\d{1,2})\b/).compactMap { match in
            guard let month = Int(match.output.1), let day = Int(match.output.2) else { return nil }
            return Mention(
                position: match.range.lowerBound,
                day: latestDate(month: month, day: day, todayStart: todayStart, calendar: calendar)
            )
        }
    }

    /// That month and day in this year, or last year when this year's is
    /// still to come ("Dec 30" said on January 2). Nil for a day that doesn't
    /// exist ("Feb 30").
    private static func latestDate(month: Int, day: Int, todayStart: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: todayStart)
        for candidateYear in [year, year - 1] {
            let parts = DateComponents(year: candidateYear, month: month, day: day)
            guard parts.isValidDate(in: calendar), let date = calendar.date(from: parts) else { return nil }
            if date <= todayStart { return date }
        }
        return nil
    }
}
