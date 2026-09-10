//
//  MCPNotebookTools+YearPlanClearing.swift
//  Maria's Notebook
//
//  Clearing a stale year plan by scope, with a preview first.
//
//  A plan generated against a sequence position a child never reached
//  accumulates dozens of planned entries with targets in the past, every one
//  of them reading as "behind pace". `update_year_plan_entry` retires one at
//  a time; `skip_year_plan_entries` retires a whole child's plan, which is
//  right for a departure and too blunt for anything else. This tool sits
//  between them: one track, or everything targeted before a day, previewed
//  before it is applied — `remove_student_from_work`'s dry-run shape.
//
//  Entries are skipped, never deleted, through the same
//  `StudentDeparturePlans.skip` the roster uses, so `year_plan(status:
//  "skipped")` still reads them and `update_year_plan_entry` can restore any
//  of them. Promoted entries are never touched — they belong to a real
//  presentation on the calendar.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static func clearYearPlanTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "clear_year_plan",
            title: "Clear Year Plan",
            description: "Skip a student's still-planned year-plan entries in bulk — the whole "
                + "plan, one track, or only entries targeted before a day — for a plan that has "
                + "gone stale. Called without confirm it only reports how many entries would be "
                + "skipped and lists them by track; nothing is written until it is called again "
                + "with confirm: true. Entries are skipped, never deleted: year_plan with status "
                + "\"skipped\" reads them back and update_year_plan_entry restores any of them. "
                + "Entries already promoted onto the calendar are left alone.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "track": [
                        "type": "string",
                        "description": .string("Only entries in this track, as year_plan shows it — "
                            + "\"Math::Fractions\", \"Math › Fractions\", or just \"Fractions\"")
                    ],
                    "before_date": [
                        "type": "string",
                        "description": "Only entries targeted before this day, YYYY-MM-DD"
                    ],
                    "confirm": [
                        "type": "boolean",
                        "description": "Pass true, after reading the report, to skip them"
                    ]
                ],
                "required": ["student_name"]
            ],
            handler: { arguments in
                try clearYearPlan(arguments: arguments, in: context())
            }
        )
    }

    private static func clearYearPlan(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudentReference(requireString(arguments, "student_name"), in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        let track = nonEmpty(arguments["track"]?.stringValue)
        let before = try dayArgument(arguments, "before_date").map(AppCalendar.startOfDay)

        let planned = StudentDeparturePlans.plannedEntries(for: studentID, in: modelContext)
        let entries = planned.filter { entry in
            if let track, !yearPlanTrack(entry.sequenceGroupKey, matches: track) { return false }
            if let before {
                guard let target = entry.plannedDate, target < before else { return false }
            }
            return true
        }
        let scope = clearScopeDescription(track: track, before: before)
        guard !entries.isEmpty else {
            let tracks = Set(planned.map(\.sequenceGroupKey)).sorted().map(trackLabel)
            let hint = tracks.isEmpty ? "" : " Planned tracks: \(tracks.joined(separator: ", "))."
            return "\(student.fullName) has no planned year-plan entries\(scope).\(hint)"
        }

        let report = clearReport(entries, in: modelContext)
        guard arguments["confirm"]?.boolValue == true else {
            return "clear_year_plan refused — nothing has been changed.\n"
                + "Re-call with confirm: true to skip these \(entries.count) entr\(entries.count == 1 ? "y" : "ies") "
                + "for \(student.fullName)\(scope).\n\n" + report
        }

        let skipped = StudentDeparturePlans.skip(entries: entries)
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The year-plan entries could not be saved.")
        }
        return "Skipped \(skipped) year-plan entr\(skipped == 1 ? "y" : "ies") for \(student.fullName)\(scope). "
            + "Nothing was deleted — read them back with year_plan status \"skipped\".\n\n" + report
    }

    /// Entries grouped by track, each in `year_plan`'s own line shape.
    private static func clearReport(_ entries: [CDYearPlanEntry], in modelContext: NSManagedObjectContext) -> String {
        let lessons = lessonNameIndex(in: modelContext)
        let byTrack = Dictionary(grouping: entries, by: \.sequenceGroupKey)
        let satisfaction = YearPlanSatisfaction.index(for: entries, in: modelContext)
        let behind = entries.filter { $0.isBehindPace(satisfiedBy: satisfaction) }.count
        var sections: [String] = []
        if behind > 0 { sections.append("\(behind) of \(entries.count) had gone behind pace.") }
        for key in byTrack.keys.sorted() {
            let group = byTrack[key] ?? []
            let lines = group.map {
                "- " + yearPlanEntryLine($0, lessons: lessons, satisfiedBy: satisfaction)
            }
            sections.append("\(trackLabel(key)) (\(group.count)):\n" + lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    /// A track argument matches an entry's `sequenceGroupKey` ("Area::Sequence")
    /// as the whole key, the "Area › Sequence" form year_plan's readers see,
    /// or the sequence alone.
    static func yearPlanTrack(_ key: String, matches track: String) -> Bool {
        let parts = key.components(separatedBy: "::")
        let sequence = parts.count > 1 ? parts[1] : key
        return sameFiling(key, track) || sameFiling(trackLabel(key), track) || sameFiling(sequence, track)
    }

    private static func trackLabel(_ key: String) -> String {
        key.isEmpty ? "No track" : key.replacingOccurrences(of: "::", with: " › ")
    }

    private static func clearScopeDescription(track: String?, before: Date?) -> String {
        var parts: [String] = []
        if let track { parts.append("in \(track)") }
        if let before { parts.append("targeted before \(dayString(before))") }
        return parts.isEmpty ? "" : " " + parts.joined(separator: " and ")
    }
}
