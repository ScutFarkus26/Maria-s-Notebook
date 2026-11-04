//
//  MCPNotebookTools+RecallChecks.swift
//  Cosmic Daybook
//
//  Recall checks: the spaced follow-up weeks after mastery, saying whether
//  a lesson actually took. (Practice sessions, which shared this file, are
//  check-ins now; plan "Simplify the app, round two", Phase 2.)
//

import CoreData
import Foundation

extension MCPNotebookTools {

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

        // `since` replaces the rolling window; `until` caps it, and alone
        // moves the rolling window back to end there.
        let cutoff: Date = window.floor(daysBack: daysBack, now: AppCalendar.startOfDay(Date()))

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
                ? "No recall checks\(who)\(window.phrase(daysBack: daysBack))."
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
