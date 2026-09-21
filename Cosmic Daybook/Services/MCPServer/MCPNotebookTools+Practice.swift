//
//  MCPNotebookTools+Practice.swift
//  Cosmic Daybook
//
//  Practice sessions and recall checks — the two records that say whether a
//  lesson actually took.
//
//  A practice session carries the qualitative marks a guide makes while
//  watching a child work: quality, independence, whether they asked for help
//  or helped a peer, whether something clicked. Recall checks are the spaced
//  follow-up: weeks later, do they still have it?
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Practice Sessions

    static func practiceSessionsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "practice_sessions",
            title: "Practice Sessions",
            description: "Recorded practice: how long a child worked, how it went, and what the "
                + "guide noticed — breakthroughs, struggles, asking for help, helping a peer, "
                + "readiness for a check-in or assessment. Filter to one student, or to sessions "
                + "carrying a particular signal. Sixty days by default; raise limit or pass "
                + "since/until (YYYY-MM-DD) to go further back.",
            inputSchema: practiceSessionsSchema,
            annotations: .readOnly,
            handler: { arguments in
                try describePracticeSessions(arguments: arguments, in: context())
            }
        )
    }

    private static var practiceSessionsSchema: JSONValue {
        var properties: [String: JSONValue] = [
            "student_name": [
                "type": "string",
                "description": "Only sessions this student took part in"
            ],
            "days_back": [
                "type": "integer",
                "description": "How many days back to look, 1-365 (default 60). Ignored when since is given."
            ],
            "signal": [
                "type": "string",
                "enum": [
                    "madeBreakthrough", "struggledWithConcept", "needsReteaching",
                    "askedForHelp", "helpedPeer", "readyForCheckIn", "readyForAssessment"
                ],
                "description": "Only sessions the guide flagged this way"
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum sessions to return, 1-50 (default 20)"
            ]
        ]
        properties.merge(dayWindowSchema("sessions worked")) { current, _ in current }
        return ["type": "object", "properties": .object(properties)]
    }

    private static func describePracticeSessions(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try nonEmpty(arguments["student_name"]?.stringValue)
            .map { try resolveStudentReference($0, in: modelContext) }
        let studentKey: String? = student?.id?.uuidString
        let daysBack: Int = intArgument(arguments, "days_back", default: 60, range: 1...365)
        let window: DayWindow = try dayWindowArgument(arguments)
        let signal: String? = nonEmpty(arguments["signal"]?.stringValue)
        let limit: Int = intArgument(arguments, "limit", default: 20, range: 1...50)

        // `since` replaces the rolling window; `until` caps it.
        let cutoff: Date = window.start ?? AppCalendar.shared.date(
            byAdding: .day, value: -daysBack, to: AppCalendar.startOfDay(Date())
        ) ?? .distantPast

        let all: [CDPracticeSession] = modelContext.safeFetch(CDFetchRequest(CDPracticeSession.self))
        var kept: [CDPracticeSession] = []
        for session in all {
            guard let date = session.date, date >= cutoff else { continue }
            if let ceiling = window.endExclusive, date >= ceiling { continue }
            if let studentKey, !session.studentIDsArray.contains(studentKey) { continue }
            if let signal, !hasSignal(session, signal) { continue }
            kept.append(session)
        }
        guard !kept.isEmpty else {
            let who = student.map { " for \($0.fullName)" } ?? ""
            return window.isSet
                ? "No practice sessions\(who)\(window.phrase)."
                : "No practice sessions\(who) in the last \(daysBack) days."
        }

        let sorted: [CDPracticeSession] = kept.sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
        let shown: [CDPracticeSession] = Array(sorted.prefix(limit))
        let names = studentNameIndex(in: modelContext)
        var lines: [String] = ["\(sorted.count) practice session(s):"]
        for session in shown {
            lines.append(contentsOf: practiceLines(session, names: names))
        }
        if sorted.count > shown.count {
            lines.append("(\(sorted.count - shown.count) more not shown.)")
        }
        return lines.joined(separator: "\n")
    }

    private static func practiceLines(
        _ session: CDPracticeSession, names: [String: String]
    ) -> [String] {
        let id: String = session.id?.uuidString ?? "unknown"
        let who: [String] = session.studentIDsArray.compactMap { names[$0] }.sorted()
        var details: [String] = [who.isEmpty ? "no students linked" : who.joined(separator: ", ")]
        if let duration = session.durationFormatted {
            details.append(duration)
        }
        if let quality = session.practiceQualityLabel {
            details.append("quality: \(quality)")
        }
        if let independence = session.independenceLevelLabel {
            details.append("independence: \(independence)")
        }
        if let location = nonEmpty(session.location) {
            details.append("in \(location)")
        }

        var lines: [String] = [
            "- [practiceSession id=\(id)] \(dayString(session.date)) — \(details.joined(separator: "; "))"
        ]
        let behaviors: [String] = session.activeBehaviors
        if !behaviors.isEmpty {
            lines.append("    Noticed: \(behaviors.joined(separator: ", "))")
        }
        if let materials = nonEmpty(session.materialsUsed) {
            lines.append("    Materials: \(materials)")
        }
        if let shared = nonEmpty(session.sharedNotes) {
            lines.append("    \(shared)")
        }
        if let followUp = nonEmpty(session.followUpActions) {
            lines.append("    Follow-up: \(followUp)")
        }
        if let checkIn = session.checkInScheduledFor {
            lines.append("    Check-in scheduled \(dayString(checkIn))")
        }
        return lines
    }

    private static func hasSignal(_ session: CDPracticeSession, _ signal: String) -> Bool {
        switch signal {
        case "madeBreakthrough": return session.madeBreakthrough
        case "struggledWithConcept": return session.struggledWithConcept
        case "needsReteaching": return session.needsReteaching
        case "askedForHelp": return session.askedForHelp
        case "helpedPeer": return session.helpedPeer
        case "readyForCheckIn": return session.readyForCheckIn
        case "readyForAssessment": return session.readyForAssessment
        default: return true
        }
    }

    // MARK: - Recall Checks

    static func recallChecksTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "recall_checks",
            title: "Recall Checks",
            description: "Spaced recall: lessons re-checked weeks after mastery, and whether the "
                + "child still had it (retained), needed a brush-up (shaky), or had lost it "
                + "(forgotten). Use this to find what is slipping rather than inferring it from "
                + "presentation dates. Ninety days by default; pass since/until (YYYY-MM-DD) to "
                + "go further back.",
            inputSchema: recallChecksSchema,
            annotations: .readOnly,
            handler: { arguments in
                try describeRecallChecks(arguments: arguments, in: context())
            }
        )
    }

    private static var recallChecksSchema: JSONValue {
        var properties: [String: JSONValue] = [
            "student_name": [
                "type": "string",
                "description": "Only this student's checks"
            ],
            "outcome": [
                "type": "string",
                "enum": ["retained", "shaky", "forgotten"],
                "description": "Only checks with this outcome"
            ],
            "days_back": [
                "type": "integer",
                "description": "How many days back to look, 1-365 (default 90). Ignored when since is given."
            ]
        ]
        properties.merge(dayWindowSchema("checks made")) { current, _ in current }
        return ["type": "object", "properties": .object(properties)]
    }

    private static func describeRecallChecks(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try nonEmpty(arguments["student_name"]?.stringValue)
            .map { try resolveStudentReference($0, in: modelContext) }
        let studentKey: String? = student?.id?.uuidString
        let daysBack: Int = intArgument(arguments, "days_back", default: 90, range: 1...365)
        let window: DayWindow = try dayWindowArgument(arguments)
        let outcome: RecallOutcome? = try recallOutcomeArgument(arguments, "outcome")

        // `since` replaces the rolling window; `until` caps it.
        let cutoff: Date = window.start ?? AppCalendar.shared.date(
            byAdding: .day, value: -daysBack, to: AppCalendar.startOfDay(Date())
        ) ?? .distantPast

        let all: [CDLessonRecallCheck] = modelContext
            .safeFetch(CDFetchRequest(CDLessonRecallCheck.self))
        var kept: [CDLessonRecallCheck] = []
        for check in all {
            guard let checkedAt = check.checkedAt, checkedAt >= cutoff else { continue }
            if let ceiling = window.endExclusive, checkedAt >= ceiling { continue }
            if let studentKey, check.studentID != studentKey { continue }
            if let outcome, check.outcome != outcome { continue }
            kept.append(check)
        }
        guard !kept.isEmpty else {
            let who = student.map { " for \($0.fullName)" } ?? ""
            return window.isSet
                ? "No recall checks\(who)\(window.phrase)."
                : "No recall checks\(who) in the last \(daysBack) days."
        }

        let names = studentNameIndex(in: modelContext)
        let sorted: [CDLessonRecallCheck] = kept.sorted {
            ($0.checkedAt ?? .distantPast) > ($1.checkedAt ?? .distantPast)
        }
        let lines = sorted.map { check -> String in
            let id: String = check.id?.uuidString ?? "unknown"
            let child: String = names[check.studentID] ?? "unknown student"
            let lesson: String = recallLessonName(check, in: modelContext) ?? "a lesson"
            var details: [String] = [check.outcome.rawValue]
            if let mastered = check.originalMasteredAt {
                details.append("mastered \(dayString(mastered))")
            }
            let note: String = nonEmpty(check.note).map { " — \($0)" } ?? ""
            return "- [recallCheck id=\(id)] \(dayString(check.checkedAt)) \(child): "
                + "\(lesson) (\(details.joined(separator: "; ")))\(note)"
        }
        return "\(sorted.count) recall check(s):\n" + lines.joined(separator: "\n")
    }

    private static func recallLessonName(
        _ check: CDLessonRecallCheck, in modelContext: NSManagedObjectContext
    ) -> String? {
        guard let uuid = UUID(uuidString: check.lessonID) else { return nil }
        return modelContext.object(CDLesson.self, id: uuid)?.name
    }

    private static func recallOutcomeArgument(
        _ arguments: [String: JSONValue], _ key: String
    ) throws -> RecallOutcome? {
        guard let raw = nonEmpty(arguments[key]?.stringValue) else { return nil }
        guard let outcome = RecallOutcome(rawValue: raw) else {
            let allowed = RecallOutcome.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("\(key) must be one of: \(allowed). Got \"\(raw)\".")
        }
        return outcome
    }
}
